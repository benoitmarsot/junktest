SET search_path TO public;
-- comment 2
create table if not exists core.users (
    userid serial,
    name varchar(50) not null,
    email varchar(100) not null,
    password varchar(100),
    role varchar(20) default 'user',
    created timestamp not null default now()
);

create table if not exists core.usersecret (
    userid int not null,
    prid int not null,
    label varchar(25) not null,
    value varchar(255) not null
);

create table core.projectresource (
    prid serial,
    projectid int not null,
    uri varchar(512) not null,
    restype varchar(20) not null -- git, file, zip, slack, web, article, etc, ...
);

create table if not exists core.oaifile (
    fid serial,
    prid int not null,
    oai_f_id varchar(30) not null,
    file_name varchar(255) not null,
    rootdir varchar(1024) not null,
    filepath varchar(1024),
    purpose varchar(20) default 'assistants',
    linecount int not null
);

create table if not exists core.vectorstore (
    vsid serial,
    oai_vs_id text not null,
    projectid int not null,
    vs_name text not null,
    vs_desc text null,
    created timestamp not null default now(),
    dayskeep int null,
    type varchar(20) not null --: code, markup, config, full
);

create table if not exists core.vectorstore_oaifile (
    vsid int not null,
    fid int not null
);

create table if not exists core.socialuser (
    userid varchar(32) not null,
    prid int not null,
    fname varchar(50) not null,
    email varchar(320) null
);

create table if not exists core.socialchannel (
    channelid varchar(20) not null,
    prid int not null,
    channelname varchar(50) not null,
    lastmessagets varchar(30) not null
);
create table if not exists core.socialassistant (
    aid serial,
    oai_aid varchar(30) not null,
    projectid int not null,
    name varchar(256) not null,
    description varchar(512) null,
    instruction text not null,
    reasoningeffort varchar(20) not null,
    model varchar(20) not null,
    temperature float not null,
    maxresults int not null default(10),
    vsid int not null,
    created timestamp not null default now()
);

create table if not exists core.assistant (
    aid serial,
    oai_aid varchar(30) not null,
    projectid int not null,
    name varchar(256) not null,
    description varchar(512) null,
    instruction text not null,
    reasoningeffort varchar(20) not null,
    model varchar(20) not null,
    temperature float not null,
    maxresults int not null default(10),
    codevsid int not null,
    markupvsid int not null,
    configvsid int not null,
    -- vector store that contains the sum of codevsid, markupvsid and configvsid 
    fullvsid int not null,
    created timestamp not null default now()
);

create table if not exists core.thread (
    threadid serial,
    oai_threadid varchar(31) not null,
    vsid int null,
    did int not null,
    type varchar(20) not null -- code, markup, config, full
);

-- the same message in different theads will be stored in the same table,
-- - the internal msgid will be used to identify the message
-- - the openai msgid is different for each thread and is not keeped in the database
-- the msgid of the db is kept in the openai metadata of the message
create table if not exists core.message (
    msgid serial,
    did int not null, -- discussion id
    role varchar(20) not null, -- system, user or assistant
    authorid int not null,
    message text not null,
    contextedmsg text null, -- the message with the context
    socialreference jsonb null, -- JSON representation of SocialReference
    created timestamp DEFAULT now()
);

create table if not exists core.project (
    projectid serial,
    name varchar(256) not null,
    description varchar(512) null,
    authorid int not null,
    isdeleted boolean default false
);

create table if not exists core.discussion (
    did serial,
    projectid int not null,
    name varchar(256) null,
    description varchar(512) null,
    isfavorite boolean default false,
    assistanttype varchar(20) not null, -- codechat, social
    created timestamp DEFAULT now()
);

create table if not exists core.sharedproject (
    projectid int not null,
    userid int not null
);

create table core.chunk (
    chunkid serial,
    projectid int not null,
    uri varchar(2048) not null,
    authorid varchar(128) null,  
    chunktype varchar(20) not null, -- code, markup, config, full, social, image
    content text not null,
    start int not null,
    embedding vector(768), -- assuming openai's ada-002 model
    metadata jsonb,         -- metadata like {"type": "method", "language": "java"}
    created_at timestamp default current_timestamp
);
