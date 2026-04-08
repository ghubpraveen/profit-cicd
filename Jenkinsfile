pipeline {
    agent any

    // triggers {
    //     pollSCM('* * * * *')
    // }

    environment {
        SCRIPT_PATH = "/home/praveen/app_scripts/deploy.sh"
    }

    stages {
        stage('Process Commit') {
            steps {
                script {
                    // Try to get hash from env; if null, fetch it from git directly
                    def commitHash = env.GIT_COMMIT ?: sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    def fullHash = commitHash
                    def branchName = env.GIT_BRANCH ?: sh(script: 'git rev-parse --abbrev-ref Head' returnStdout: true).trim()
                    
                    echo "Processing Commit: ${fullHash}"
                    
                    // Call the script and pass the hash
                    sh "bash ${env.SCRIPT_PATH} ${fullHash} ${branchName}"
                }
            }
        }
    }
}
