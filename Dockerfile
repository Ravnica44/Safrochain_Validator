# Safrochain Node Dockerfile

FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    make \
    gcc \
    curl \
    jq \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Go
RUN wget https://go.dev/dl/go1.23.9.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.23.9.linux-amd64.tar.gz \
    && rm go1.23.9.linux-amd64.tar.gz

# Set environment variables
ENV GOPATH=/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

# Set working directory
WORKDIR /app

# Clone the Safrochain repository
RUN rm -rf safrochain-node && \
    git clone https://github.com/Safrochain-Org/safrochain-node.git

WORKDIR /app/safrochain-node

# Build the binary
RUN make install

# Install the binary
RUN cp /go/bin/safrochaind /usr/local/bin/

# Create the data directory
RUN mkdir -p /data/.safrochain

# Set home directory
ENV HOME=/data
WORKDIR /data

# Command to run the node
ENTRYPOINT ["safrochaind"]
CMD ["start", "--home=/data"]