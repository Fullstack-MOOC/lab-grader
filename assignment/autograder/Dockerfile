FROM cypress/base:22.12.0

# Install required system dependencies in one layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bc \
        jq \
        curl \
        wget \
        unzip && \
    rm -rf /var/lib/apt/lists/*

# Switch to Node.js 20 LTS to avoid npm/node regressions with newer releases
RUN npm install -g n@9.2.0 && \
    n 20.18.1 && \
    npm install -g npm@10.8.2 && \
    npm cache clean --force
ENV PATH="/usr/local/n/versions/node/20.18.1/bin:${PATH}"

# Install specific Cypress version to match project using Node 20
RUN npm install -g cypress@13.17.0

WORKDIR /grader

# Install Cypress binary for the specific version
RUN cypress install

COPY grader.sh ./
RUN chmod +x grader.sh

ENTRYPOINT ["./grader.sh"]
