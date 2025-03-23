package com.unbumpkin.codechat.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.unbumpkin.codechat.dto.request.AddOaiThreadRequest;
import com.unbumpkin.codechat.dto.request.DiscussionNameSuggestion;
import com.unbumpkin.codechat.dto.request.DiscussionUpdateRequest;
import com.unbumpkin.codechat.dto.request.MessageCreateRequest;
import com.unbumpkin.codechat.model.Discussion;
import com.unbumpkin.codechat.model.Message;
import com.unbumpkin.codechat.model.openai.Assistant;
import com.unbumpkin.codechat.model.openai.OaiThread;
import com.unbumpkin.codechat.repository.DiscussionRepository;
import com.unbumpkin.codechat.repository.MessageRepository;
import com.unbumpkin.codechat.repository.openai.AssistantRepository;
import com.unbumpkin.codechat.repository.openai.OaiFileRepository;
import com.unbumpkin.codechat.repository.openai.OaiThreadRepository;
import com.unbumpkin.codechat.service.openai.ChatService;
import com.unbumpkin.codechat.service.openai.OaiMessageService;
import com.unbumpkin.codechat.service.openai.OaiRunService;
import com.unbumpkin.codechat.service.openai.OaiThreadService;
import com.unbumpkin.codechat.service.openai.CCProjectFileManager.Types;
import com.unbumpkin.codechat.service.openai.BaseOpenAIClient.Models;
import com.unbumpkin.codechat.service.openai.BaseOpenAIClient.Roles;

import java.io.IOException;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/discussions")
public class DiscussionController {

    @Autowired
    private DiscussionRepository discussionRepository;
    @Autowired
    private MessageRepository messageRepository;
    @Autowired
    private AssistantRepository assistantRepository;
    @Autowired
    private OaiThreadService threadService;
    @Autowired
    private OaiThreadRepository threadRepository;
    @Autowired
    ObjectMapper objectMapper;
    @Autowired 
    OaiThreadService oaiThreadService;
    @Autowired
    OaiFileRepository oaiFileRepository;



    @PostMapping
    public ResponseEntity<Discussion> createDiscussion(
        @RequestBody Discussion discussionRequest
    ) throws IOException {
        Discussion discussion=discussionRepository.addDiscussion(discussionRequest);
        Assistant assistant=assistantRepository.getAssistantByProjectId(discussion.projectId());
        String oaiThreadId=threadService.createThread();
        System.out.println("OpenAi thread " + oaiThreadId+" created...");
        threadRepository.addThread(new AddOaiThreadRequest(oaiThreadId, assistant.codevsid(),discussion.did(), "code"));

        return ResponseEntity.ok(discussion);
    }
    @PostMapping("/ask-question")
    public ResponseEntity<Message> askQuestion(
        @RequestBody MessageCreateRequest request
    ) throws IOException {
        try {
            Message returnedMessage=messageRepository.addMessage(request);
            Discussion discussion=discussionRepository.getDiscussionById(returnedMessage.discussionId());
            Map<Types,OaiThread> threadMap=threadRepository.getAllThreadsByDiscussionId(discussion.did());
            OaiThread thread=threadMap.get(Types.code);
            OaiMessageService messageService=new OaiMessageService(thread.oaiThreadId());
            String oaiMsgId=messageService.createMessage(Roles.user,returnedMessage.message());
            System.out.println("OpenAi message " + oaiMsgId+" created...");
            return ResponseEntity.ok(returnedMessage);
        } catch (Exception e) {
            System.out.println("exception in askQuestion: " + e.getMessage());
            e.printStackTrace();
            throw e;
        }
    }
    @PostMapping("/{did}/answer-question")
    public ResponseEntity<Message> answerQuestion(@PathVariable int did) throws IOException {
        Discussion discussion = discussionRepository.getDiscussionById(did);
        Assistant assistant = assistantRepository.getAssistantByProjectId(discussion.projectId());
        Map<Types, OaiThread> threadMap = threadRepository.getAllThreadsByDiscussionId(did);
        OaiThread thread = threadMap.get(Types.code);
        OaiRunService runService = new OaiRunService(assistant.oaiAid(), thread.oaiThreadId());
        OaiMessageService msgService = new OaiMessageService(thread.oaiThreadId());
        String OaiRunId = runService.create();
        System.out.println("Starting OpenAi run " + OaiRunId + "...");
        System.out.println("Waiting for answer...");
        runService.waitForAnswer(OaiRunId);
    
        JsonNode jsonNode = msgService.retrieveMessage(msgService.listMessages().get(0));
        JsonNode answerNode = jsonNode.findValue("value");
    
        // Decide if the node is textual or structured
        String answer = answerNode.isTextual() 
            ? answerNode.asText()
            : objectMapper.writeValueAsString(answerNode);
        
        System.out.println("AI Answer: " + answer);
        // If you need to replace references:
        // Set<String> refFiles = AnswerUtils.getReferencesFileIds(answer);
        // List<OaiFile> refFileMap = oaiFileRepository.retrieveFiles(refFiles.toArray(String[]::new));
        // answer = AnswerUtils.replaceferencesFileIds(answer, refFileMap);
    
        // Validate JSON only if it’s structured
        try {
            JsonNode validated = objectMapper.readTree(answer);
            answer = objectMapper.writeValueAsString(validated);
        } catch (Exception e) {
            System.out.println("Answer is not valid JSON: " + e.getMessage());
        }
    
        // Clean up special chars
        answer = answer.replaceAll("[\\p{Cc}&&[^\r\n\t]]", "");
    
        Message message = messageRepository.addMessage(
            new MessageCreateRequest(did, Roles.assistant.toString(), answer)
        );
        return ResponseEntity.ok(message);
    }

    @GetMapping("/{did}")
    public ResponseEntity<Discussion> getDiscussion(@PathVariable int did) {
        return ResponseEntity.ok(discussionRepository.getDiscussionById(did));
    }

    @GetMapping("/project/{projectId}")
    public ResponseEntity<List<Discussion>> getDiscussionsByProject(@PathVariable int projectId) {
        return ResponseEntity.ok(discussionRepository.getAllDiscussionsByProjectId(projectId));
    }

    @PutMapping("/{did}")
    public ResponseEntity<Discussion> updateDiscussion(@PathVariable int did, @RequestBody DiscussionUpdateRequest updateRequest) {
        Discussion discussion=discussionRepository.updateDiscussion(updateRequest);
        return ResponseEntity.ok(discussion);
    }

    @GetMapping("{did}/suggest")
    public ResponseEntity<DiscussionNameSuggestion[]> suggestName(
        @PathVariable int did
    ) throws JsonProcessingException, IOException {
        ChatService chatService=new ChatService(
            Models.gpt_4o, 
            """
            You are a great software engineer and you are working on a project. 
            You need to suggest 5 meaningfull names and descriptions for a discussion. 
            Your answer should be formatted as a json array: [{"name": "name1", "description": "description1"}, {"name": "name2", "description": "description2"}, {"name": "name3", "description": "description3"}],
            name should be less than 25 characters long, and represent a title for the discussion, it can use up to 5 words separated by space.
            your descriptions should be less than 225 characters long.
            """,
            1f
        );
        List<Message> messages=messageRepository.getAllMessagesByDiscussionId(did);
        String json=objectMapper.writeValueAsString(messages);
        chatService.addMessage("user", json);
        String answer=chatService.answer();
        String jsonResponse=answer.substring(answer.indexOf("```json")+7, answer.lastIndexOf("```"));
        DiscussionNameSuggestion[] suggestions = objectMapper.readValue(jsonResponse, DiscussionNameSuggestion[].class);
        return ResponseEntity.ok(suggestions);
    }
    

    @DeleteMapping("/{did}")
    public ResponseEntity<Void> deleteDiscussion(@PathVariable int did) {
        discussionRepository.deleteDiscussion(did);
        return ResponseEntity.ok().build();
    }
}
