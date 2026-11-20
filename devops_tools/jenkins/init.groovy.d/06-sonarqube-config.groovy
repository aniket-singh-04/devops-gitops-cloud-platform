// ──────────────────────────────────────────────────────────────
// Jenkins Init Script 6: Configure SonarQube Server as Code
// Configures SonarQube installation endpoint for Jenkins pipelines
// ──────────────────────────────────────────────────────────────
import jenkins.model.*

try {
    def instance = Jenkins.getInstance()
    def env = System.getenv()
    def sonarUrl = env.getOrDefault('SONARQUBE_URL', 'http://sonarqube:9000')
    def sonarToken = env.getOrDefault('SONAR_TOKEN', '')

    def sonarDescriptor = instance.getDescriptorByName("hudson.plugins.sonar.SonarGlobalConfiguration")
    if (sonarDescriptor != null) {
        def sonarInstallationClass = Class.forName("hudson.plugins.sonar.SonarInstallation")
        def constructor = sonarInstallationClass.getConstructor(
            String.class, String.class, String.class, String.class, String.class,
            Class.forName("hudson.plugins.sonar.model.TriggersConfig"), String.class, String.class, String.class
        )
        def installation = constructor.newInstance(
            "SonarQube-Local",
            sonarUrl,
            sonarToken,
            null,
            null,
            null,
            null,
            null,
            null
        )
        sonarDescriptor.setInstallations(installation)
        sonarDescriptor.save()
        println "--> [JCasC Init] SonarQube server configuration registered: ${sonarUrl}"
    } else {
        println "--> [JCasC Init] SonarQube plugin descriptor not loaded yet; skipping SonarGlobalConfiguration."
    }
} catch (Exception e) {
    println "--> [JCasC Init] SonarQube registration note: ${e.message}"
}
