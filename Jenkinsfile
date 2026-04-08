pipeline {
    agent any
    
    triggers {
        pollSCM('* * * * *')
    }

    environment {
        SCRIPT_PATH = "/home/praveen/app_scripts/deploy.sh"
    }

//     stages {
//         stage('Process Commit') {
//             steps {
//                 script {
//                     // Try to get hash from env; if null, fetch it from git directly
//                     def commitHash = env.GIT_COMMIT ?: sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
//                     def fullHash = commitHash
//                     def branchName = env.GIT_BRANCH ?: sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
                    
//                     echo "Processing Commit: ${fullHash}"
//                     echo "Processing Branch: ${branchName}"
                    
                    
//                     // Call the script and pass the hash
//                     sh "bash ${env.SCRIPT_PATH} ${fullHash} ${branchName}"
//                 }
//             }
//         }
//     }
// }

       stages {
        stage('Collect Data & Deploy') {
            steps {
                script {
                    // 1. Gather Variables
                    def fullHash = env.GIT_COMMIT ?: sh(script: "git rev-parse -- HEAD", returnStdout: true).trim()
                    def branch = env.GIT_BRANCH ?: sh(script: "git rev-parse --abbrev-ref HEAD", returnStdout: true).trim()
                    branch = branch.replaceAll('origin/', '').replaceAll('remotes/', '')
                    def buildNum = env.BUILD_NUMBER
                    def cause = currentBuild.getBuildCauses()[0].shortDescription
                    
                    // 2. Pass them to the script as arguments
                    // Order: $1=hash, $2=branch, $3=buildNum, $4=cause
                    sh "bash ${env.SCRIPT_PATH} '${fullHash}' '${branch}' '${buildNum}' '${cause}'"
                }
            }
        }
    }
}
 