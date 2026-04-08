pipeline {
    agent any

    triggers {
        pollSCM('* * * * *')
    }
   
    environment {
        SCRIPT_PATH = "/home/praveen/deploy.sh"
    }

    stages {
        stage('Process Commmit') {
            steps{
                script{
                    def shortHash = env.GIT_COMMIT.take(7)
                    echo "Processing Commit: ${shortHash}"
                    sh "bash ${env.SCRIPT_PATH} ${shortHash}"
                }
            }
        }
    }

}
