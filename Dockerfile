FROM itmicus/cmdbuild:4.1.0

USER root
RUN apt-get update && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*

COPY patches/oauth/ /usr/local/tomcat/webapps/cmdbuild/WEB-INF/classes/org/cmdbuild/auth/login/oauth/
COPY entrypoint/entrypoint.sh /usr/local/bin/entry.sh
RUN chmod +x /usr/local/bin/entry.sh

USER tomcat
ENTRYPOINT ["/usr/local/bin/entry.sh"]