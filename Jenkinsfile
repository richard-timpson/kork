// The support_gradle branch has modifications to mavenStageArtifacts to make it work
// without a pom
@Library('sfci-pipeline-sharedlib@support_gradle') _

import net.sfdc.dci.BuildUtils
import net.sfdc.dci.GitHubUtils
import net.sfdc.dci.GusComplianceUtils

// Kubernetes kills the pod that's executing us unless we give it enough memory.  Dynamic
// resourcing doesn't appear to be enough.  At least
//
// [INFO]:[executePipeline]: DYNAMIC RESOURCE IDENTIFIED:[mem:3.264498176Gi, cpu:2, mvn_mem:2319m]
//
// isn't enough to stay alive.  So, disable dynamic resourcing.  Even then,
// medium still isn't big enough whether building inside a spinnaker-build
// container or 'directly' in a java11 container, without spinnaker-build, so
// use large.
def envDef = [
  // See https://confluence.internal.salesforce.com/display/public/ZEN/What+are+the+build+docker+images+managed+by+SFCI
  buildImage: '331455399823.dkr.ecr.us-east-2.amazonaws.com/sfci/sfci/centos7-sfci-jdk11-maven:397fbce',
  disableConcurrentBuilds: true,
  flavor: 'large',
  useDynamicResourcing: false
]

// The trigger to release upstream kork artifacts is pushing a tag that matches
// a regex.  From
// e.g. https://github.com/spinnaker/kork/blob/1e237160b990ffe6aa5181ffc514818bac58a973/.github/workflows/release.yml#L3-L7
//
// on:
//  push:
//    tags:
//    - "v[0-9]+.[0-9]+.[0-9]+"
//    - "v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+"
//
// which effectively means someone creates a tag in their local clone, and by
// pushing the tag to github.com, github releases a jar.
//
// The other thing to note is that the version comes from the tag itself, not
// from e.g. gradle.properties.
//
// That's generally the desired behavior here too, though we also need to comply
// with rules about released artifacts -- that they've been reviewed.  So,
// "just" pushing a tag isn't enough.  We need to also make sure that we're
// releasing from a branch that requires reviews, and has the other validations
// for releasable artifacts.
//
// So, the goal is to "do nothing" (i.e. NOT trigger publishing a jar) when a PR
// lands on a release branch.  Instead, set up the appropriate logic to trigger
// this job runs when a tag arrives on a release branch.  Based on the above
// validations, the code is OK to release.  The presence of the tag actually
// initiates the release process, and provides the version.  This way we also
// don't release on every commit to a release branch, which may lead to a lot of
// churn.
//
// Use the same branch convention as the other spinnaker microservice repos.
env.RELEASE_BRANCHES = ['release-1.21.x-sfcd', 'release-1.23.x-sfcd' ]

executePipeline(envDef) {
  // Adjust the snyk timeout since scanning takes longer than the default (currently 5
  // minutes).  From
  // https://sfcirelease.dop.sfdc.net/job/spinnaker/job/spinnaker-kork-Jenkinsfile/job/kork/job/release-1.23.x-sfcd/2/console
  // it took ~10.43 minutes:
  //
  // 11:40:12    "durationMs": 626065
  //
  // so use a bigger number to give some buffer
  //
  // Instructions from
  // https://confluence.internal.salesforce.com/display/public/ZEN/Snyk+CI+Integration#SnykCIIntegration-SnykScancustomarguments
  env.snykTimeoutInMins = 15

  boolean publish = false
  String versionToRelease
  String workItem
  String gradleVersionOption = ''
  stage('Init') {
    // We need to inspect tags to see what to do.  Something like (from
    // https://www.jenkins.io/doc/pipeline/steps/build-steps-from-json/):
    //
    // checkout([
    //   $class: 'GitSCM',
    //   branches: scm.branches,
    //   extensions: scm.extensions + [[$class: 'CloneOption', noTags: false, reference: '', shallow: false]],
    //   userRemoteConfigs: scm.userRemoteConfigs
    // ])
    //
    // would normally accomplish that.  However GitHubUtilsImpl.checkoutGitRepoIfRequired
    // takes over and doesn't honor these options, so explicitly fetch tags ourselves.  As
    // well, executePipeline has already fetched and I don't see a way to convince it to
    // fetch tags as well.
    checkout scm

    mavenInit()
    gradleInit()

    def commitSha = BuildUtils.getLatestCommitSha(this)
    echo "The commit sha is ${commitSha}"
    def statusCode = sh(returnStatus: true, script: 'git fetch --tags --quiet')
    if (statusCode != 0) {
      error "git fetch failed (${statusCode})"
    }
    if (BuildUtils.isReleaseBuild(env)) {
      echo "on a release branch"
      // Figure out if the current commit has any tags associated with it
      def existingTags = sh([returnStdout: true, script: "git tag -l --points-at ${commitSha}"]).trim().tokenize('\n')
      echo "existingTags: '${existingTags}'"

      def releaseTags = existingTags.findAll { tag -> tag ==~ /v[0-9]+.[0-9]+.[0-9]+/ }
      echo "releaseTags: '${releaseTags}'"

      // If there's more than one release tag, we don't know which one to use, so bail
      if (releaseTags.size() > 1) {
        error "more than one release tag (${releaseTags})...not sure which one to use"
      }

      if (releaseTags.size() == 1) {
        // Make sure the commit has a work item, otherwise we can't make
        // version-bumping PRs that pass the required checks
        echo 'looking for work item in commit message'
        def commitMessage = ""
        def commitContent = GitHubUtils.getCommit(this, commitSha)
        if (commitContent.commit) {
          commitMessage = commitContent.commit.message
        }
        if (!commitMessage) {
          error "no commit message from which to parse work item (sha: ${commitSha}, commitContent: ${commitContent}"
        }
        Set<String> workItems = GusComplianceUtils.getAtMentionsOfGusWorkId(commitMessage)
        if (workItems.isEmpty()) {
          error "no work item in commit message '${commitMessage}' (sha: ${commitSha}), unable to make valid autobump PR"
        }
        // arbitrarily choose a work item from the set
        workItem = (workItems as List)[0]

        echo "workItem: '${workItem}'"

        publish = true
        // Strip the leading v from the tag
        versionToRelease = releaseTags[0].substring(1)
        gradleVersionOption = "ORG_GRADLE_PROJECT_version=${versionToRelease}"
        echo "publishing version ${versionToRelease}"
      } else {
        echo "no release tag -- not publishing"
      }
    } else {
      echo "not on a release branch"
    }
  }

  stage('Build') {
    try {
      withCredentials([usernamePassword(credentialsId: 'sfci-nexus', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
        // Specifying the version doesn't change what happens here, but it provides a
        // verison to snyk which makes the output / results easier to digest.  Without one
        // the version is "unspecified".  Note that the version is still unspecified unless
        // we're publishing.
        //
        // Specify TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX since testcontainers uses
        // docker.io by default, which isn't accessible from jenkins.  See
        // https://www.testcontainers.org/features/image_name_substitution/#automatically-modifying-docker-hub-image-names.
        sh "${gradleVersionOption} TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX='dva-registry.internal.salesforce.com/sfci/3pp/3pp/docker.io/' ./gradlew build"
      }
    } finally {
      // Not really specific to maven.  This publishes junit test results.
      mavenPostBuild('**/build/test-results/**/*.xml')
    }
  }

  if (publish) {
    stage('Publish') {
      // Publish the artifacts to the repository at ${workspace}/sfci-target/deploy, from
      // where it'll be picked up and promoted to nexus releases.
      //
      // From
      // https://docs.gradle.org/6.0.1/release-notes.html#publication-of-sha256-and-sha512-checksums,
      // don't publish SHA256/SHA512 because salesforce nexus complains that
      // they're not overwriteable.
      String gradleOptions = "${gradleVersionOption} ORG_GRADLE_PROJECT_repositoryDir=${workspace}/sfci-target/deploy GRADLE_OPTS='-Dorg.gradle.daemon=false -Xmx2g -Xms2g'"
      def result=sh(returnStdout: true, script: "${gradleOptions} ./gradlew publishSpinnakerPublicationToSalesforceRepository -Dorg.gradle.internal.publish.checksums.insecure=true")

      println "Staging artifacts"
      mavenStageArtifacts([version: versionToRelease])

      println "Promoting artifacts"
      // artifactPath is for logging...and difficult to get from build.gradle, so hard
      // code it.
      mavenPromoteArtifacts([version: versionToRelease, artifactPath: 'com.salesforce.spinnaker.kork'])
    }

    stage('Dependency bump') {
      echo 'creating PRs to bump kork dependency'
      String dockerImage = 'dva-registry.internal.salesforce.com/sfci/spinnaker/bumpdeps:latest'
      def DOCKER_REGISTRY_HOST = 'dva-registry.internal.salesforce.com'
      def dockerRegistry = "https://${DOCKER_REGISTRY_HOST}"
      def image = docker.image(dockerImage)
      docker.withRegistry(dockerRegistry) {
         image.pull()
      }
      withCredentials([usernamePassword(credentialsId: 'sfci-nexus', usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD'),
                       usernamePassword(credentialsId: 'sfci-git', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GITHUB_OAUTH')]) {
        def dockerArgs = [
          '-e NEXUS_USERNAME',
          '-e NEXUS_PASSWORD',
          '-e GITHUB_OAUTH'
        ].join(' ')

        if (!workItem) {
          error "no work item...can't autobump"
        }
        def bumpdepsArgs = [
          "--work-item ${workItem}",
          "--ref refs/tags/v$versionToRelease",
          '--key korkVersion',
          // assume the branch naming convention in the target repos matches this one
          "--base-branch ${BuildUtils.getCurrentBranch(this)}",
          '--repositories clouddriver,echo,fiat,front50,gate,igor,orca,rosco',
          '--repo-owner spinnaker',
          '--upstream-owner spinnaker',
          '--maven-repository-url https://nexus-proxy-prd.soma.salesforce.com/nexus/content/groups/public',
          '--group-id com.salesforce.spinnaker.kork',
          '--artifact-id kork-bom', // arbitrary choice of one of the kork artifacts
          '--github-url https://git.soma.salesforce.com',
          '--github-api-endpoint https://git.soma.salesforce.com/api/v3'
          ].join(' ')
        sh "docker run $dockerArgs $dockerImage $bumpdepsArgs"
      }
    }
  }
}
