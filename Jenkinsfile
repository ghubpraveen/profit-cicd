pipeline {
    agent any

    parameters {
        string(name: 'JOB_NAME', defaultValue: '', description: 'Job Name (e.g., My-Java-App)')
        string(name: 'BRANCH', defaultValue: 'master', description: 'Git Branch to pull')
        string(name: 'BUILD_ENV', defaultValue: 'UAT', description: 'Target Environment')
        choice(name: 'REQUIRED', choices: ['Build', 'Files_Copy', 'Build_And_Files_Copy'], description: 'Action to perform')
        string(name: 'WORKSPACE_PATH', defaultValue: '/var/jenkins_home/workspace', description: 'Path to workspace')
        choice(name: 'VALIDATE_HASHES', choices: ['no', 'yes'], description: 'Smart Build (Skip if no changes)')
        string(name: 'BUILD_USER', defaultValue: 'Jenkins-Admin', description: 'User triggering the build')
        string(name: 'RAM_Memory', defaultValue: '8192', description: 'Node RAM limit for frontend')
    }

    environment {
        // Software paths from your script
        JAVA_HOME = "/u01/sfw/jdk-17.0.5"
        M2_HOME   = "/u01/sfw/apache-maven-3.6.3"
        PATH      = "${JAVA_HOME}/bin:${M2_HOME}/bin:${env.PATH}"
        
        // GChat URL from your original script
        GCHAT_URL = "https://chat.googleapis.com/v1/spaces/AAAAkRPquRE/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=8P_S4Exea74xKAFnKua2-q7Tnaawpkk7hwhESi8L4f0&messageReplyOption=REPLY_MESSAGE"
        
        // Script location on server
        SCRIPT_PATH = "/u01/scripts/java_deployment.sh"
    }

    stages {
        stage('Deploy Process') {
            steps {
                script {
                    // Running the shell script with all 8 parameters
                    sh """
                        bash ${env.SCRIPT_PATH} \
                        '${params.JOB_NAME}' \
                        '${params.BRANCH}' \
                        '${params.BUILD_ENV}' \
                        '${params.REQUIRED}' \
                        '${params.WORKSPACE_PATH}' \
                        '${params.VALIDATE_HASHES}' \
                        '${params.BUILD_USER}' \
                        '${params.RAM_Memory}'
                    """
                }
            }
        }
    }

    post {
        success {
            script {
                // Replicating your script's success message
                def timeSeconds = currentBuild.duration / 1000
                sh """
                    curl -sH 'Content-Type: application/json' -X POST ${env.GCHAT_URL} \
                    -d '{"text": "✅ *${params.JOB_NAME} Build Successful*\\nEnvironment: ${params.BUILD_ENV}\\nUser: ${params.BUILD_USER}\\nDuration: ${timeSeconds}s"}'
                """
            }
        }
        failure {
            script {
                // Replicating your script's failure/alert message
                sh """
                    curl -sH 'Content-Type: application/json' -X POST ${env.GCHAT_URL} \
                    -d '{"text": "❌ *${params.JOB_NAME} Build Failed*\\nEnvironment: ${params.BUILD_ENV}\\nCheck logs at: ${env.BUILD_URL}console"}'
                """
            }
        }
    }
}
