#!/bin/bash
set -e

TOMCAT_HOME=/usr/local/tomcat
CMDBUILD_CLI="$TOMCAT_HOME/webapps/cmdbuild/cmdbuild.sh"
FLAG_FILE=/usr/local/tomcat/conf/cmdbuild_configured

echo "=== CMDBUILD CONTAINER INITIALIZATION START ==="

# Esegui setup solo la prima volta
if [ ! -f "$FLAG_FILE" ]; then
    echo "→ Prima configurazione CMDBuild..."

    # ✅ Ricreo database (drop + create empty)
    echo "→ Ricreo database (drop + create empty)..."
    bash $CMDBUILD_CLI dbconfig drop || echo "(Database non esistente, ignoro errore)"
    bash $CMDBUILD_CLI dbconfig create empty

    # ✅ Avvia Tomcat in background per consentire configurazione via REST
    echo "→ Avvio Tomcat in background..."
    $TOMCAT_HOME/bin/catalina.sh start

    echo "→ Attendo che CMDBuild sia completamente operativo..."


    # Attesa UI (Tomcat attivo)
    until curl -sf http://localhost:8080/cmdbuild/ui >/dev/null 2>&1; do
        echo "   Attesa UI..."
        sleep 5
    done
    echo "   UI pronta, verifico disponibilità backend..."
    
    # Attesa REST API (considera 200 o 401 come ok)
    until curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/cmdbuild/services/rest/v3/session/status | grep -Eq "200|401"; do
        echo "   Attesa backend..."
        sleep 5
    done
    
    echo "✅ CMDBuild completamente operativo, procedo con la configurazione OAuth."


    # ✅ Configurazione Authentik (se presente)
    if [ -n "$AUTHENTIK_SERVICE_URI" ]; then
        echo "→ Configuro integrazione Authentik..."
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.serviceUrl "$AUTHENTIK_SERVICE_URI"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.protocol "$AUTHENTIK_OAUTH_PROTOCOL"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.redirectUrl "$AUTHENTIK_CMDBUILD_REDIRECT_URL"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.clientId "$AUTHENTIK_CMDBUILD_CLIENT_ID"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.clientSecret "$AUTHENTIK_CMDBUILD_CLIENT_SECRET"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.modules "$CMDBUILD_AUTH_MODULES"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.scope "$AUTHENTIK_CMBDUILD_OPENID_SCOPE"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.login.type "$AUTHENTIK_CMBDUILD_OPENID_LOGIN_TYPE"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.login.attr "$AUTHENTIK_CMBDUILD_OPENID_LOGIN_ATTRIBUTE"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.description "$AUTHENTIK_CMBDUILD_OPENID_LOGIN_DESCRIPTION"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.protocol "$AUTHENTIK_CMBDUILD_OPENID_PROTOCOL"
        bash $CMDBUILD_CLI restws setconfig org.cmdbuild.auth.module.oauth.logout.enabled "$AUTHENTIK_CMBDUILD_OPENID_LOGOUT_ENABLED"
    else
        echo "⚠️  Variabili Authentik non trovate — salto configurazione OAuth."
    fi

    # ✅ Segna come completato
    touch "$FLAG_FILE"
    echo "✅ Prima configurazione completata."
else
    echo "→ Configurazione già eseguita, salto setup."
fi

# ✅ Mantieni Tomcat in foreground per Docker
echo "→ Avvio Tomcat in foreground..."
exec $TOMCAT_HOME/bin/catalina.sh run