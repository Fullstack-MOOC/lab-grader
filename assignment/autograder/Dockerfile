FROM --platform=linux/amd64 cypress/base:22.12.0

WORKDIR /grader

# Update package lists and upgrade vulnerable packages
RUN apt-get update && \
    apt-get upgrade -y \
        libxml2 \
        libxml2-dev \
        libglib2.0-0 \
        libglib2.0-dev \
        wget && \
    apt-get install -y bc jq && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g cypress@13.17.0
RUN npx cypress install
RUN npx cypress verify

COPY grader.sh ./
RUN chmod +x grader.sh

# COPY grade.js ./

ENTRYPOINT ["./grader.sh"]

