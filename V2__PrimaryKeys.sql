SET search_path TO public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_pkey') THEN
        ALTER TABLE core.users ADD CONSTRAINT user_pkey PRIMARY KEY (userid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'oaifile_pkey') THEN
        ALTER TABLE core.oaifile ADD CONSTRAINT oaifile_pkey PRIMARY KEY (fid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vectorstore_pkey') THEN
        ALTER TABLE core.vectorstore ADD CONSTRAINT vectorstore_pkey PRIMARY KEY (vsid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vectorstore_oaifile_pkey') THEN
        ALTER TABLE core.vectorstore_oaifile ADD CONSTRAINT vectorstore_oaifile_pkey PRIMARY KEY (vsid, fid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'assistant_pkey') THEN
        ALTER TABLE core.assistant ADD CONSTRAINT assistant_pkey PRIMARY KEY (aid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'thread_pkey') THEN
        ALTER TABLE core.thread ADD CONSTRAINT thread_pkey PRIMARY KEY (threadid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'message_pkey') THEN
        ALTER TABLE core.message ADD CONSTRAINT message_pkey PRIMARY KEY (msgid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_pkey') THEN
        ALTER TABLE core.project ADD CONSTRAINT project_pkey PRIMARY KEY (projectid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'discussion_pkey') THEN
        ALTER TABLE core.discussion ADD CONSTRAINT discussion_pkey PRIMARY KEY (did);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sharedproject_pkey') THEN
        ALTER TABLE core.sharedproject ADD CONSTRAINT sharedproject_pkey PRIMARY KEY (projectid, userid);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'usersecret_pkey') THEN
        ALTER TABLE core.usersecret ADD CONSTRAINT usersecret_pkey PRIMARY KEY (userid,prid,label);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'projectresource_pkey') THEN
        ALTER TABLE core.projectresource ADD CONSTRAINT projectresource_pkey PRIMARY KEY (prid);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'socialuser_pkey') THEN
        ALTER TABLE core.socialuser ADD CONSTRAINT socialuser_pkey PRIMARY KEY (userid,prid);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'socialassistant_pkey') THEN
        ALTER TABLE core.socialassistant ADD CONSTRAINT socialassistant_pkey PRIMARY KEY (aid);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'socialchannel_pkey') THEN
        ALTER TABLE core.socialchannel ADD CONSTRAINT socialchannel_pkey PRIMARY KEY (channelid,prid);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chunk_pkey') THEN
        ALTER TABLE core.chunk ADD CONSTRAINT chunk_pkey PRIMARY KEY (chunkid);
    END IF;
END $$;