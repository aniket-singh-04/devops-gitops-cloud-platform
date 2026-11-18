// ──────────────────────────────────────────────────────────────
// Jenkins Init Script 2: Create DockerHub Credentials as Code
// Adds 'dockerhub-credentials' to System Credentials Provider
// ──────────────────────────────────────────────────────────────
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import hudson.util.Secret

def instance = Jenkins.getInstance()
def domain = Domain.global()
def systemStore = instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')

if (systemStore && systemStore.size() > 0) {
    def store = systemStore[0].getStore()
    def env = System.getenv()
    def dhUser = env.getOrDefault('DOCKERHUB_USERNAME', 'aniket04')
    def dhPass = env.getOrDefault('DOCKERHUB_PASSWORD', 'default_token')

    // Check if dockerhub-credentials already exists
    def existing = store.getCredentials(domain).find { it.id == 'dockerhub-credentials' }
    if (existing == null) {
        def credentials = new UsernamePasswordCredentialsImpl(
            CredentialsScope.GLOBAL,
            'dockerhub-credentials',
            'DockerHub Registry Credentials (Automated via Init Script)',
            dhUser,
            dhPass
        )
        store.addCredentials(domain, credentials)
        println "--> [JCasC Init] Successfully registered 'dockerhub-credentials' for user: ${dhUser}"
    } else {
        println "--> [JCasC Init] 'dockerhub-credentials' already exists."
    }
} else {
    println "--> [JCasC Init] Note: Credentials plugin store not yet ready."
}
