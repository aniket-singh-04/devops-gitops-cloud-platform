// ──────────────────────────────────────────────────────────────
// Jenkins Init Script 3: Configure Global Tools (NodeJS) as Code
// Configures 'node26' tool descriptor if NodeJS plugin is loaded
// ──────────────────────────────────────────────────────────────
import jenkins.model.*
import hudson.tools.*

def instance = Jenkins.getInstance()
def desc = instance.getDescriptor("jenkins.plugins.nodejs.tools.NodeJSInstallation")

if (desc != null) {
    try {
        def installations = desc.getInstallations() as List
        def existing = installations.find { it.name == 'node26' }
        if (existing == null) {
            def clazz = Class.forName("jenkins.plugins.nodejs.tools.NodeJSInstallation")
            def constructor = clazz.getConstructor(String.class, String.class, List.class)
            def inst = constructor.newInstance('node26', '', [])
            installations.add(inst)
            desc.setInstallations(installations.toArray(new hudson.tools.ToolInstallation[0]))
            desc.save()
            println "--> [JCasC Init] Registered NodeJS global tool: 'node26'"
        } else {
            println "--> [JCasC Init] NodeJS global tool 'node26' already exists."
        }
    } catch (Exception e) {
        println "--> [JCasC Init] NodeJS tool registration note: ${e.message}"
    }
}
