FROM amazon/aws-cli

RUN yum install -y \
    net-tools \
    jq \
    nmap-ncat \
    && \
    yum clean all

COPY ./custodian .
COPY ./dns-updater .
COPY ./event-emitter .
COPY ./task-reaper .

ENTRYPOINT ["./watchdog.sh"]