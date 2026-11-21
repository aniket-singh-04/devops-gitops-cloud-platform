// ──────────────────────────────────────────────────────────────
// Jenkins Init Script 4: Create CI Pipeline Job as Code
// Automatically provisions 'devops-ci-pipeline'
// ──────────────────────────────────────────────────────────────
import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.UserRemoteConfig
import java.util.Collections

def instance = Jenkins.getInstance()
def repoUrl = 'https://github.com/aniket-singh-04/Complete-deployment.git'
def branch = '*/main'
def scriptPath = 'devops_tools/jenkins/Jenkinsfile.ci'

def jobName = 'devops-ci-pipeline'

try {
    def job = instance.getItem(jobName)
    if (job == null) {
        job = instance.createProject(WorkflowJob.class, jobName)
        println "--> [JCasC Init] Created WorkflowJob: '${jobName}'"
    }

    def branchSpec = Collections.singletonList(new BranchSpec(branch))
    def remoteConfig = Collections.singletonList(new UserRemoteConfig(repoUrl, null, null, null))
    def scm = new GitSCM(remoteConfig, branchSpec, false, Collections.emptyList(), null, null, Collections.emptyList())

    def flowDefinition = new CpsScmFlowDefinition(scm, scriptPath)
    flowDefinition.setLightweight(true)
    job.setDefinition(flowDefinition)

    job.save()
    instance.save()
    println "--> [JCasC Init] Pipeline job '${jobName}' configured with '${scriptPath}'"
} catch (Exception e) {
    println "--> [JCasC Init] Pipeline job creation note for ${jobName}: ${e.message}"
}
