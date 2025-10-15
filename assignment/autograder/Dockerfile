FROM --platform=linux/amd64 cypress/base:22.12.0

WORKDIR /grader

ENV DEBIAN_FRONTEND=noninteractive \
    COURSES_GRADING=true \
    CI=true \
    NODE_ENV=test \
    MONGOMS_VERSION=7.0.14 \
    MONGOMS_SYSTEM_BINARY=/usr/bin/mongod \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# System dependencies, MongoDB, and common CLI tooling
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        ca-certificates && \
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg && \
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        mongodb-org-server \
        mongodb-mongosh \
        bc \
        jq \
        dos2unix \
        wget \
        unzip \
        netcat-openbsd \
        iputils-ping && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /data/db

# Ensure corepack (pnpm/yarn) is available without prompts
RUN corepack enable

# Cypress setup (pre-install to leverage cache layers)
RUN npm install -g npm@latest && \
    npm install -g cypress@13.17.0 && \
    npx cypress install && \
    npx cypress verify

# Bring in everything available in the build context (Dockerfile uploader may only include grader.zip)
COPY . .

# If grader.zip is present (Coursera often uploads only the zip), unzip it.
# Then normalize line endings and set execute bits only for files that exist.
RUN if [ -f grader.zip ]; then unzip -o grader.zip; fi && \
    if [ -f grader.sh ]; then dos2unix grader.sh && chmod +x grader.sh; fi && \
    if [ -f aggregate-results.js ]; then dos2unix aggregate-results.js && chmod +x aggregate-results.js; fi

RUN mkdir -p /autograder/results

ENTRYPOINT ["/bin/bash","-lc","./grader.sh"]

