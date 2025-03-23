package com.unbumpkin.codechat.controller;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.io.File;
import java.io.IOException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.unbumpkin.codechat.service.openai.AssistantBuilder;
import com.unbumpkin.codechat.service.openai.AssistantService;
import com.unbumpkin.codechat.service.openai.OaiFileService;
import com.unbumpkin.codechat.service.openai.VectorStoreFile;
import com.unbumpkin.codechat.service.openai.AssistantBuilder.ReasoningEffort;
import com.unbumpkin.codechat.service.openai.BaseOpenAIClient.Models;
import com.unbumpkin.codechat.service.openai.GithubRepoContentManager;
import com.unbumpkin.codechat.service.openai.CCProjectFileManager;
import static com.unbumpkin.codechat.service.openai.CCProjectFileManager.getFileType;
import com.unbumpkin.codechat.service.openai.CCProjectFileManager.Types;
import com.unbumpkin.codechat.service.openai.VectorStoreService;
import com.unbumpkin.codechat.util.ExtMimeType;
import com.unbumpkin.codechat.util.FileUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.unbumpkin.codechat.dto.FileRenameDescriptor;
import com.unbumpkin.codechat.dto.GitHubChangeTracker;
import com.unbumpkin.codechat.dto.request.CreateProjectRequest;
import com.unbumpkin.codechat.dto.request.CreateVSFileRequest;
import com.unbumpkin.codechat.model.Project;
import com.unbumpkin.codechat.model.ProjectResource;
import com.unbumpkin.codechat.model.UserSecret;
import com.unbumpkin.codechat.model.UserSecret.Labels;
import com.unbumpkin.codechat.model.openai.Assistant;
import com.unbumpkin.codechat.model.openai.OaiFile;
import com.unbumpkin.codechat.model.openai.VectorStore;
import com.unbumpkin.codechat.model.openai.OaiFile.Purposes;
import com.unbumpkin.codechat.model.openai.VectorStore.VectorStoreResponse;
import com.unbumpkin.codechat.repository.DiscussionRepository;
import com.unbumpkin.codechat.repository.MessageRepository;
import com.unbumpkin.codechat.repository.ProjectRepository;
import com.unbumpkin.codechat.repository.ProjectResourceRepository;
import com.unbumpkin.codechat.repository.openai.AssistantRepository;
import com.unbumpkin.codechat.repository.openai.OaiFileRepository;
import com.unbumpkin.codechat.repository.openai.OaiThreadRepository;
import com.unbumpkin.codechat.repository.openai.VectorStoreRepository;
import com.unbumpkin.codechat.repository.openai.VectorStoreRepository.RepoVectorStoreResponse;
import com.unbumpkin.codechat.security.CustomAuthentication;

import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;


@RestController
@RequestMapping("/api/v1/codechat")
public class CodechatController {
    @Autowired
    private AssistantRepository assistantRepository;
    @Autowired
    private ProjectRepository projectRepository;
    @Autowired
    private OaiFileRepository oaiFileRepository;
    @Autowired
    private OaiFileService oaiFileService;
    @Autowired
    private VectorStoreRepository vsRepository;
    @Autowired
    private VectorStoreService vsService;
    @Autowired
    private AssistantService assistantService;
    @Autowired 
    private MessageRepository messageRepository;
    @Autowired
    private OaiThreadRepository threadRepository;
    @Autowired
    DiscussionRepository discussionRepository;
    @Autowired
    ProjectResourceRepository projectResourceRepository;
    

    private int getCurrentUserId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof CustomAuthentication) {
            return ((CustomAuthentication) authentication).getUserId();
        }
        throw new IllegalStateException("No authenticated user found");
    }

    @DeleteMapping("delete-all")
    public ResponseEntity<String> deleteAll(
    ) throws IOException {
        oaiFileService.cleanUpFiles();
        vsService.cleanUpVectorStores();
        assistantService.cleanUpAssistants();
        
        // Delete all records in the message table
        messageRepository.deleteAll();
        // Delete all records in the thread table
        threadRepository.deleteAll();
        // Delete all records in the assistant table
        assistantRepository.deleteAll();
        // Delete all records in the vectorstore table
        // - and the vectorstore_oaifile associations
        vsRepository.deleteAll();
        // Delete all records in the oaifile table
        oaiFileRepository.deleteAll();            
        // Delete all records in the sharedproject table
        projectRepository.deleteAll();
        // Delete all records in the discussion table
        //  - including vectorstore_discussion associations
        discussionRepository.deleteAll();
        // Delete all records in the project table
        projectRepository.deleteAll();
        return ResponseEntity.ok("All data deleted");
    }

    @Transactional
    @PostMapping("create-empty-project")
    public ResponseEntity<Project> createEmptyProject(
        @RequestBody CreateProjectRequest request
    ) throws Exception {
        int projectId=projectRepository.addProject(request.name(), request.description());
        if(projectId==0){
            throw new Exception("project could not be created.");
        }
        System.out.println("project created with id: "+projectId);
        Map<String,Integer> vectorStorMap = new LinkedHashMap<>();

        //Here the order is important because the assistant will use the vector stores in this order
        // Code, Markup, then Config
        System.out.println("Create empty vector store for code files...");
        createEmptyVectorStore( projectId, "vsCode",  Types.code, vectorStorMap);
        System.out.println("Create empty vector store for markup files...");
        createEmptyVectorStore( projectId, "vsMarkup",  Types.markup, vectorStorMap);
        System.out.println("Create vector store for config files...");
        createEmptyVectorStore( projectId, "vsConfig",  Types.config, vectorStorMap);
        System.out.println("Create vector store for all files...");
        String vsAlOaid=createEmptyVectorStore( projectId, "vsAll",  Types.all, vectorStorMap);
        System.out.println("Create assistant...");
        int assistantId=createAssistant(request.name(), projectId, vectorStorMap,vsAlOaid);
        System.out.println("Assistant created with id: "+assistantId);
        Project project = new Project(projectId, request.name(), request.description(), this.getCurrentUserId(), assistantId);
        return ResponseEntity.ok(project);
    }

    @Transactional
    @PostMapping("{projectId}/refresh-repo")
    public ResponseEntity<Void> refreshRepo(
        @PathVariable int projectId
    ) throws Exception {
        GithubRepoContentManager pfc=new GithubRepoContentManager();
        List<ProjectResource> resources = projectResourceRepository.getResources(projectId);
        Map<Types,RepoVectorStoreResponse> vsMap = CCProjectFileManager.getVectorStoretMap(
            vsRepository.getVectorStoresByProjectId(projectId)
        );
        Map<Types,VectorStoreFile> vsfServicesMap = new HashMap<>(3);
        vsfServicesMap.put(Types.code, new VectorStoreFile(vsMap.get(Types.code).vsid()));
        vsfServicesMap.put(Types.config, new VectorStoreFile(vsMap.get(Types.config).vsid()));
        vsfServicesMap.put(Types.markup, new VectorStoreFile(vsMap.get(Types.markup).vsid()));
        VectorStoreFile vsfServicesAll = new VectorStoreFile(vsMap.get(Types.all).vsid());

        for (ProjectResource resource : resources) {
            if (resource.uri() != null) {
                try {
                    String branch=resource.secrets().get(Labels.branch).value();
                    String oldCommitHash=resource.secrets().get(Labels.commitHash).value();
                    String commitHash=pfc.getLatestCommitHash(resource.uri(), branch);
                    if(commitHash.equals(oldCommitHash)){
                        System.out.println("No changes in the repo "+resource.uri());
                        continue;
                    }
                    GitHubChangeTracker changes=pfc.getChangesSinceCommitViaGitHubAPI( 
                        resource.uri(), oldCommitHash, branch
                    );
                    int tempDirLength=pfc.getTempDir().length();
                    for (String deletedFile : changes.deletedFiles()) {
                        // try {
                            OaiFile oaiFile = oaiFileRepository.getOaiFileByPath(deletedFile, resource.prId());
                            if(oaiFile!=null){
                                Types fileType=getFileType(oaiFile.fileName());
                                vsfServicesMap.get(fileType).removeFile(oaiFile.fileId());
                                vsfServicesAll.removeFile(oaiFile.fileId());
                                oaiFileService.deleteFile(oaiFile.fileId());
                                oaiFileRepository.deleteFile(oaiFile.fileId());
                                System.out.println(oaiFile.filePath()+" id "+oaiFile.fileId()+" removed from "+fileType.toString()+" vector store and deleted.");
                            }
                        // } catch (Exception e) {
                        //     System.out.println("Should be removed: Error deleting file: "+deletedFile);
                        // }
                    }

                    for (String addedFile : changes.addedFiles()) {
                        File file = new File(pfc.getTempDir()+"/"+addedFile);
                        FileRenameDescriptor desc = ExtMimeType.oaiRename(file);
                        OaiFile oaiFile = oaiFileService.uploadFile(desc.newFile().getAbsolutePath(), tempDirLength+1, Purposes.assistants, resource.prId());
                        System.out.println("file "+file.getName()+" uploaded with id "+oaiFile.fileId());
                        String oldExt = FileUtils.getFileExtension(desc.oldFileName());
                        Types fileType=getFileType(desc.oldFileName());
                        CreateVSFileRequest request = new CreateVSFileRequest(
                            oaiFile.fileId(), new HashMap<>() {{
                                put("name", desc.oldFileName());
                                put("path", desc.oldFilePath().substring(tempDirLength+1));
                                put("extension", oldExt);
                                // Should I put the "."? If so put it in the assistant instructions
                                put("mime-type", ExtMimeType.getMimeType(oldExt));
                                put("nbLines", String.valueOf(FileUtils.countLines(desc.newFile())));
                                put("type", fileType.name());
                            }}
                        );
                        vsfServicesMap.get(fileType).addFile( request);
                        vsfServicesAll.addFile( request);
                        oaiFileRepository.storeOaiFile(oaiFile, oaiFile.prId());

                        System.out.println("File id "+oaiFile.fileId()+" added to "+fileType.toString()+" vector store ");
                    }
                    projectResourceRepository.updateSecret(resource.prId(), Labels.commitHash, commitHash);
                } catch (Exception e) {
                    e.printStackTrace();
                    throw e;
                } finally {
                    pfc.deleteRepository();
                }
            }
        }
        return ResponseEntity.ok().build();
    }

    
    @Transactional
    @PostMapping("create-project")
    public ResponseEntity<Project> createProject(
        @RequestBody CreateProjectRequest request
    ) throws Exception {
        GithubRepoContentManager pfc=new GithubRepoContentManager();
        try{ 
            //Test createAssistant
            // createAssistant("myProject", 24, new LinkedHashMap<>() {{
            //     put("vs_67bfff4b3f808191ab92a49f9c192eab", 42);
            // }});
            int projectId=projectRepository.addProject(request.name(), request.description());
            if(projectId==0){
                throw new Exception("project could not be created.");
            }
            System.out.println("project created with id: "+projectId);
            String sourcePath = "";
            if(request.repoURL()!=null){
                pfc=new GithubRepoContentManager(request.username(), request.password());
                sourcePath=pfc.addRepository(request.repoURL(), request.branch());
            } else {
                throw new Exception("Repo url is required");
            }
            //Create project resource
            Map<Labels,UserSecret> userSecrets = new HashMap<>();
            if(request.username()!=null && !request.username().isEmpty()){
                userSecrets.put(Labels.username, new UserSecret(Labels.username, request.username()));
                userSecrets.put(Labels.password, new UserSecret(Labels.password, request.password()));
            }
            userSecrets.put(Labels.branch, new UserSecret(Labels.branch, request.branch()));
            userSecrets.put(Labels.commitHash, new UserSecret(Labels.commitHash, pfc.getCommitHash()));
            ProjectResource pr=projectResourceRepository.createResource(projectId, request.repoURL(), userSecrets);

            int basePathLength = sourcePath.length();
            Map<String,Integer> vectorStorMap = new LinkedHashMap<>();
            Map<String,CreateVSFileRequest> allFileIds = new HashMap<>();
            //Here the order is important because the assistant will use the vector stores in this order
            // Code, Markup, then Config
            System.out.println("Uploading and create vector store for code files...");
            createVectorStore(pfc, pr.prId(), projectId, "vsCode", Types.code, allFileIds, vectorStorMap, basePathLength);
            System.out.println("Uploading and create vector store for markup files...");
            createVectorStore(pfc, pr.prId(), projectId, "vsMarkup", Types.markup, allFileIds, vectorStorMap, basePathLength);
            System.out.println("Uploading and create vector store for config files...");
            createVectorStore(pfc, pr.prId(), projectId, "vsConfig", Types.config, allFileIds, vectorStorMap, basePathLength);
            System.out.println("Create vector store for all files...");
            String vsAllOaiId=vsService.createVectorStore(
                new VectorStore("vsAll","contain all the files in the project.", 
                    null,null,null,null)
            );
            int vsAllId=vsRepository.storeVectorStore(
                new VectorStore(0, vsAllOaiId, projectId, "vsAll", 
                    "contain all the files in the project.", null, Types.all)
            );
            VectorStoreFile vsfService = new VectorStoreFile(vsAllOaiId);

            for (String oaiFileId : allFileIds.keySet()) {

                vsfService.addFile(allFileIds.get(oaiFileId));
                System.out.println("File id "+oaiFileId+" added to global vector store "+vsAllOaiId);

            }
            vectorStorMap.put(vsAllOaiId, vsAllId);
            System.out.println("Create assistant...");
            int assistantId=createAssistant(request.name(), projectId, vectorStorMap,vsAllOaiId);
            System.out.println("Assistant created with id: "+assistantId);
            Project project = new Project(projectId, request.name(), request.description(), this.getCurrentUserId(), assistantId);
            return ResponseEntity.ok(project);
        } catch (Exception e) {
            e.printStackTrace();
            throw e;
        } finally {
            pfc.deleteRepository();
        }
    }
    private String createEmptyVectorStore(
        int projectId, String vsName, Types type, Map<String,Integer> vectorStorMap
    ) throws IOException {
        String vsDesc = "contain the "+type.name()+" files in the project.";
        String vsOaiId = vsService.createVectorStore(
            new VectorStore(
                vsName, vsDesc, null, null, null, null
            )
        );
        VectorStore vs = new VectorStore(0, vsOaiId, projectId, vsName, vsDesc, null, type);
        int vsId=vsRepository.storeVectorStore(vs);
        System.out.println("Empty vector store "+type.name()+" created with id: "+vsId+" and OaiId: "+vsOaiId);
        vectorStorMap.put(vsOaiId, vsId);
        return vsOaiId;
    }
    private void createVectorStore(
        CCProjectFileManager pfc, int prId, int projectId, String vsName, Types type,
        Map<String,CreateVSFileRequest> allFileIds, Map<String,Integer> vectorStorMap,
        int basePathLength
    ) throws IOException {
        List<OaiFile> lFiles = new ArrayList<>();
        List<String> lFileIds = new ArrayList<>();
        String vsOaiId = vsService.createVectorStore(
            new VectorStore(vsName,"contain the "+type.name()+" files in the project.", 
            null,null,null,null)
        );
        System.out.println("Vector store "+type.name()+" created with id: "+vsOaiId);
        VectorStoreFile vsfService = new VectorStoreFile(vsOaiId);
        for (File file : pfc.getFileSetMap(type)) {
            FileRenameDescriptor desc = ExtMimeType.oaiRename(file);
            OaiFile oaiFile = oaiFileService.uploadFile(desc.newFile().getAbsolutePath(), basePathLength+1, Purposes.assistants, prId);
            lFiles.add(
                oaiFile
            );
            System.out.println("file "+file.getName()+" uploaded with id "+oaiFile.fileId());
            lFileIds.add(oaiFile.fileId());
            String oldExt = FileUtils.getFileExtension(desc.oldFileName());
            CreateVSFileRequest request = new CreateVSFileRequest(
                oaiFile.fileId(), new HashMap<>() {{
                    put("name", desc.oldFileName());
                    put("path", desc.oldFilePath().substring(basePathLength+1));
                    put("extension", oldExt);
                    // Should I put the "."? If so put it in the assistant instructions
                    put("mime-type", ExtMimeType.getMimeType(oldExt));
                    put("nbLines", String.valueOf(FileUtils.countLines(desc.newFile())));
                    put("type", type.name());
                }}
            );
            allFileIds.put(oaiFile.fileId(), request);
            vsfService.addFile(request);
            System.out.println("File id "+oaiFile.fileId()+" added to vector store "+vsOaiId);
        }
        oaiFileRepository.storeOaiFiles(lFiles, prId);

        //(int vsId, String oaiVsId, String vsname, String vsdesc, Instant created, Integer dayskeep, Types type)
        VectorStore vs = new VectorStore(0, vsOaiId, projectId, vsName, 
            "Contains the "+type.name()+" files in the project.", null, type);
        int vsId=vsRepository.storeVectorStore(vs);
        vsRepository.addFiles(vsOaiId, lFileIds);
        vectorStorMap.put(vsOaiId, vsId);
    }
    private int createAssistant(
        String name, int projectId, Map<String,Integer> vectorStorMap, String vsAllOaiId
    ) throws IOException {
        AssistantBuilder assistantBuilder = new AssistantBuilder(Models.o3_mini);

        assistantBuilder.setName(name)
            .setDescription("Code search assistant for " + name)
            .setInstructions("""
                You are a code search assistant designed to help users analyze and understand their projects. Your primary role is to provide detailed explanations, code snippets, and actionable suggestions based on the project's files and metadata.

                Always respond in the following structured JSON format, and do not prefix with ```<language>:
                {
                    "answers": [
                        {
                            "explanation": "<Detailed explanation>",
                            "language": "<Programming language (if applicable)>",
                            "code": "<Formatted code snippet (if applicable)>",
                            "codeExplanation": "<Explanation of the code snippet (if applicable)>",
                            "references": ["<Relevant sources>"]
                        }
                        // Add more answers as needed
                    ],
                    "conversationalGuidance": "<Additional guidance for the user: Intelligent Follow-ups, Actionable Suggestions, Engagement & Clarifications, etc.>"
                }


                Use plain text in the response.
                Markdown is supported in the explanation, code explanation, and reference fields.

                ### File Metadata Usage
                When analyzing files, use the following attributes from the file metadata to provide insights and context:
                - **`name`**: Use the file name to identify the file and provide context in your response.
                - **`path`**: Use the file's relative path to locate it within the project and reference it in your response.
                - **`extension`**: Use the file extension to determine the programming language or file type (e.g., `java` for Java, `py` for Python).
                - **`mime-type`**: Use the MIME type to understand the file's format or content type (e.g., `text/plain`, `application/json`).
                - **`nbLines`**: Use the number of lines in the file to assess its size or complexity. For example:
                - Small files (e.g., <50 lines) may be utility scripts or configuration files.
                - Large files (e.g., >500 lines) may indicate complex logic or large datasets.
                - **`type`**: Use the file type (e.g., `code`, `markup`, `config`) to tailor your analysis and suggestions. For example:
                - For `code` files, focus on programming logic, structure, and potential improvements.
                - For `markup` files, focus on formatting, structure, and content organization.
                - For `config` files, focus on configuration correctness and best practices.

                ### Analyzing Files
                - Use the `extension` and `mime-type` attributes to determine the programming language or file type. For example:
                - `java` → Java
                - `py` → Python
                - `html` → HTML
                - Use the `nbLines` attribute to assess the file's complexity and provide insights. For example:
                - "This file contains 120 lines of Java code, which suggests it implements a moderately complex class."
                - Use the `type` attribute to guide your analysis. For example:
                - For `code` files, analyze the logic, structure, and potential improvements.
                - For `markup` files, analyze the formatting and content organization.
                - For `config` files, analyze the correctness and adherence to best practices.

                ### Referencing Files
                - Donot use the internal name, always use file metadata such as `name` and `path` when referencing specific files.
                - Use the `nbLines` attribute to provide insights into the file's size or complexity when relevant.
                - Use the `mime-type` attribute to describe the file's format or content type.
                - When retrieving code, always reference the file's `path` and `name` to provide context.

                #### Markdown Links for References
                - Use Markdown links with a title attribute to reference files. For example:
                `[MyClass.java](src/main/java/com/example/MyClass.java "Java source file")`.

                ### Handling Non-Code Queries
                - If the query is not related to code, omit the `language` and `code` fields in the response. Focus on providing a clear explanation and actionable suggestions.

                ### Example Response
                {
                    "answers": [
                        {
                            "explanation": "The file `MyClass.java` contains the implementation of the main application logic. It is located at `src/main/java/com/example/MyClass.java` and contains 120 lines of Java code. The file's MIME type is `text/x-java-source`.",
                            "language": "Java",
                            "code": "public class MyClass { ... }",
                            "codeExplanation": "This code defines the main class of the application.",
                            "references": ["[MyClass.java](src/main/java/com/example/MyClass.java \"Java source file\")"]
                        }
                    ],
                    "conversationalGuidance": "Would you like to see more details about this file or related files?"
                }
                """).setReasoningEffort(ReasoningEffort.high)
            //.setTemperature(.02) //Not suported in o3-mini
            .addFileSearchTool().addFileSearchAssist()
            .setFileSearchMaxNumResults(20) //default
            //.setFileSearchRankingOption(.5) 
            .setToolResourcesFileSearch(Set.of(vsAllOaiId)) //: can only put one vs so putting vsAll 
            //Function are not needed since we use attributes metadata
            // .addFunction()
            //     .setFunctionName("countLines")
            //     .setFunctionDescription("This function will return the number of lines in a file")
            //     .FunctionAddParameter("fileid", "string", "The id of the file")
            //todo: implement get the file name from the file_id
            // .addFunction()
            //     .setFunctionName("getFilename")
            //     .setFunctionDescription("This function will return the name of file")
            //     .FunctionAddParameter("fileid", "string", "The id of the file");
            // .addFunction()
            //     .setFunctionName("isAnswerCode")
            //     .setFunctionDescription("This function will return the name of file")
            //     .FunctionAddParameter("fileid", "string", "The id of the file");
            ;
        ObjectMapper mapper = new ObjectMapper();
        mapper.enable(SerializationFeature.INDENT_OUTPUT);
        String assistantJson = mapper.writeValueAsString(assistantBuilder);
        System.out.println(assistantJson);
        mapper.writeValueAsString(assistantBuilder);
        String assistantOaiId=assistantService.createAssistant(assistantBuilder);
        Integer[] vsIds = vectorStorMap.values().toArray(new Integer[0]);
        Assistant assistant = new Assistant(0, assistantOaiId, name, "Code search assistant for " + name,
            projectId, vsIds[0], vsIds[1], vsIds[2], vsIds[3]
        );
        return assistantRepository.addAssistant(assistant);
    }

}