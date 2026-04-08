pipeline {
    agent any
   
    environment {
        SCRIPT_PATH = "/home/praveen/deploy.sh"
    }

    stages {
        stage('Process Commmit') {
            steps{
                script{
                    env.GIT_COMMIT.take (7)
                    echo "Processing Commit: ${shortHash}"
                    sh "bash ${env.SCRIPT_pATH} ${shortHash}"
                }
            }
        }
    }

