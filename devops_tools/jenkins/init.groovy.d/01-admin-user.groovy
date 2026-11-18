// ──────────────────────────────────────────────────────────────
// Jenkins Init Script 1: Disable Setup Wizard & Configure Security
// Automatically sets setup wizard as completed and creates Admin user
// ──────────────────────────────────────────────────────────────
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()

// 1. Disable the Jenkins initial setup wizard (skip "Unlock Jenkins" screen)
if (!instance.getInstallState().isSetupComplete()) {
    instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
    println "--> [JCasC Init] Jenkins setup wizard automatically disabled."
}

// 2. Resolve credentials from environment variables
def env = System.getenv()
def adminUser = env.getOrDefault('JENKINS_ADMIN_USER', 'admin')
def adminPass = env.getOrDefault('JENKINS_ADMIN_PASSWORD', 'admin123')

// 3. Ensure HudsonPrivateSecurityRealm exists
def realm = instance.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
}

// 4. Create admin user account
if (realm.getUser(adminUser) == null) {
    realm.createAccount(adminUser, adminPass)
    println "--> [JCasC Init] Created Admin user: ${adminUser}"
} else {
    println "--> [JCasC Init] Admin user ${adminUser} already exists."
}

// 5. Set authorization strategy: Logged in users can do anything
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
println "--> [JCasC Init] Security realm and admin access configured successfully."
