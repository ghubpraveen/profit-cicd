#!/bin/bash
#Purpose : Jenkins UAT AWS Auto Build and Files copy generation and Files Copy to CDN and Deployment in staigng ENV
#Created By:  Sathish.V.S
#Verified By: 
#Creation Date:  [ 23 May 2025 ]
#Modified By: NA
#Modification Date:  NA
####################################################################
set -e  # Exit on any command failure
trap 'echo "❌ Script failed at line $LINENO."' ERR

START_TIME=`date +%s`
GCP_THREAD=gcp-thread-$START_TIME
NODE_THREAD=node-thread-$START_TIME
###### Sathish testing Chat ################
#export GCHAT_URL="https://chat.googleapis.com/v1/spaces/AAAAi3EHuzc/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=0DGw9aqpUU_gLD7edRTR_PKDdLwS3f6ZXZuwQtg4H3E%3D&messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"
########## UAT GCHAT Environment ####################
export GCHAT_URL="https://chat.googleapis.com/v1/spaces/AAAAkRPquRE/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=8P_S4Exea74xKAFnKua2-q7Tnaawpkk7hwhESi8L4f0&messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"
export DEV_GCHAT_URL="https://chat.googleapis.com/v1/spaces/AAQAncj_kkw/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=Qz3EajgBpT1HaSNIIEwGGaAb1-UpdBL53KlMHXFaz7k&messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"
##############################################################
##### Files copy Generation paramater ####################
    export JOB_NAME=$1
    export BRANCH=$2
    export BUILD_ENV=$3
    export REQUIRED=$4
    export repo_workspace=$5
    export TOMCAT_BRANCH=$6
    export BUILD_CAUSE=$7
    export hostname=`hostname` 
   # export RAM_MEMORY=$8
    export VALIDATE_HASHES=$8

    if [[ "$BUILD_CAUSE" == *Timer* ]]; then
        export BUILD_USER="jenkins-bot"
    else
    # "Set Jenkins user build variables" plugin sets BUILD_USER_ID
        export BUILD_USER="${BUILD_CAUSE}"
    fi

########## Files Copy to GCP CDN Bucket parameter #################
    export Destination="/u01/jenkins/profit-FC/App"
########## Docker Image generation Paramater ############
    export NAME="Profit_UAT_App"
    export STS="app"
    export BUILD_PATH="$repo_workspace/workspace/app-tomcat"
    export WAR_NAME="app.war"
    export SRC_WAR="$repo_workspace/workspace/profit/app-web/target/app.war"
    export DEST_WAR="$BUILD_PATH/app/live/profit/webapps/app.war"
    export DEST="$BUILD_PATH/app/live/profit/webapps/"
    export PROJECT="apptivo-app-stag"
    export GCR="us-central1-docker.pkg.dev"
    export ENV="uat-build"
    export START_TIME=`date +%s`
    export THREAD=thread-$START_TIME
########## Uat Environment Bouncing Paramater ############
    export FILE_VERSION="$(cat $repo_workspace/workspace/$BUILD_ENV-fc.txt)"
    echo "$(cat $repo_workspace/workspace/$BUILD_ENV-fc.txt)"
    export CDN_BUCKET=$(/u01/jenkins/scripts/pft_fn_GCP_And_AWS_CDN_Bucket_AND_URL.sh $BUILD_ENV GCP_CDN_BUCKET)
    export CDN_URL=$(/u01/jenkins/scripts/pft_fn_GCP_And_AWS_CDN_Bucket_AND_URL.sh $BUILD_ENV GCP_CDN_URL)
    export AWS_S3_BUCKET=$(/u01/jenkins/scripts/pft_fn_GCP_And_AWS_CDN_Bucket_AND_URL.sh $BUILD_ENV AWS_S3_BUCKET)
    export AWS_S3_URL=$(/u01/jenkins/scripts/pft_fn_GCP_And_AWS_CDN_Bucket_AND_URL.sh $BUILD_ENV AWS_S3_URL)

########################################################
if [ $# == 8 ] ;
then

send_alert() {
	curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Hi '$BUILD_USER', \n'*$JOB_NAME*' is Failed, Please check", "thread" : { "threadKey": "THREAD-'$(date +%s)'"}}' >> /dev/null
    exit 1
}

trap 'send_alert; exit 1' ERR
##################################
GIT_PULL() {
    set -e
    trap 'echo "❌ Error: git operation failed"; exit 1' ERR

    local JOB_ACTION=$1     # Action label for message
    local GIT_REQUIRED=$2       # Type of action: Build, Files_Copy, etc.

    echo "📥 Fetching updates from remote for branch: $BRANCH"
    git fetch origin "$BRANCH"
    git checkout -f "$BRANCH"
    git pull origin "$BRANCH"

    echo "GIT_REQUIRED=$GIT_REQUIRED"

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    REVISION=$(git rev-parse HEAD)

    echo "🔍 Current branch: $CURRENT_BRANCH"
    echo "🔍 Current revision: $REVISION"

    sleep 1

    Build_HASH_FILE="$repo_workspace/workspace/$BUILD_ENV-app-buildinfo.txt"
    FC_HASH_FILE="$repo_workspace/workspace/$BUILD_ENV-app-FCinfo.txt"

    [[ -f "$Build_HASH_FILE" ]] && LAST_BUILD_HASH=$(awk '{print $3}' "$Build_HASH_FILE")
    [[ -f "$FC_HASH_FILE" ]] && LAST_FC_HASH=$(awk '{print $3}' "$FC_HASH_FILE")

    declare -A LAST_HASHES=(
        ["Build"]="${LAST_BUILD_HASH:-}"
        ["Files_Copy"]="${LAST_FC_HASH:-}"
    )

    if [[ -z "$GIT_REQUIRED" ]]; then
        echo "❌ ERROR: No REQUIRED argument passed"
        exit 1
    fi

    echo "🔁 Validate Hashes: $VALIDATE_HASHES"

    if [[ "${VALIDATE_HASHES,,}" == "yes" ]]; then
        echo "✅ Hash validation enabled"

        local expected_hash="${LAST_HASHES[$GIT_REQUIRED]}"

        if [[ "$REVISION" == "$expected_hash" ]]; then
            echo "🚫 No new commits for $GIT_REQUIRED. Skipping..."

            curl -sH 'Content-Type: application/json' -X POST "$GCHAT_URL" \
            --data '{
                "text": "Hi '"$BUILD_USER"',\n🚫 No new commit detected in branch: *'"$CURRENT_BRANCH"'*, \nSkipping the *'"${JOB_ACTION,,}"'* job.",
                "thread": { "threadKey": "THREAD-'"$(date +%s)"'" }
            }' >> /dev/null

            exit 0
        fi

        echo "✅ New commit detected: $REVISION"
        echo "🚀 Running build..."
    else
        echo "⚠️ Hash validation skipped due to parameter setting."
        echo "🚀 Running build anyway..."
    fi
}
############# Build and Files copy Hashcode info saving ################
Revision_Save_info() {
    local ACTION=$1
        if [[ -z "$ACTION" ]]; then
        echo "❌ ERROR: No ACTION passed"
        exit 1
    fi
    echo ">> DEBUG: ACTION=$ACTION"

    case "$ACTION" in
        "Files_Copy")
            echo "$ACTION alone in $BUILD_ENV Env"
            echo "Git Hash: $REVISION and Branch: $CURRENT_BRANCH" > "$repo_workspace/workspace/$BUILD_ENV-app-FCinfo.txt"
            ;;
        "Build")
            echo "$ACTION in $BUILD_ENV Env"
            echo "Git Hash: $REVISION and Branch: $CURRENT_BRANCH" > "$repo_workspace/workspace/$BUILD_ENV-app-buildinfo.txt"
            ;;
        *)
            echo "❌ ERROR: Invalid Input Request: $ACTION"
            exit 1
            ;;
    esac
    
}
########################################################################
#Files Copy Generation Function
Files_Generation()
    {

        #FC_Generate_Thread
	    free -h
        FC_START_TIME=`date +%s`
        export FCINFO=`cat $repo_workspace/workspace/$BUILD_ENV-app-FCinfo.txt`
        source /etc/profile.d/nodejs.sh
	export FC_THREAD=FC-thread-$START_TIME
	
    send_alert() {
	curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Hi '$BUILD_USER', \n'*$JOB_NAME*'\nFiles Generation is Failed,\nPlease check", "thread" : { "threadKey": "THREAD-'$(date +%s)'"}}' >> /dev/null
    exit 1
	}

#        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\nJob Name:*$JOB_NAME* initiated by *$BUILD_USER*\n*File Generation initiated* in $BUILD_ENV\n$FCINFO"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
#        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Git Pull Started in '*$BUILD_ENV*' ", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

        #==========================================================================
                echo  "GIT Pull Started"
        #==========================================================================
        trap 'echo "Error: git pull failed"; exit 1' ERR

        if [ $JOB_NAME == "UAT_Deployment_SlaveVM2_Autobuild" ]
        then

        JOB_PATH=$repo_workspace/workspace/profit-FC

        if [ ! -d $JOB_PATH ]
                then
                        mkdir -p $JOB_PATH
                        mkdir -p $JOB_PATH
                        mkdir -p $JOB_PATH/clean_source
                else
                        rm -rf $JOB_PATH/clean_source/*
            fi

        cd $JOB_PATH
        #################################
        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Git Pull Started with the latest revision", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
        echo "Git Pull Started with the latest revision"
        GIT_PULL "UAT_Deployment_Gulp" "Files_Copy" #Pull the data from Git
        #GIT_HASH_VALIDATE 
        Revision_Save_info "Files_Copy" # Save the Hashcode and CURRENT_BRANCH to Build info
            echo "$(cat $repo_workspace/workspace/$BUILD_ENV-fc.txt)"
            echo "$(cat $repo_workspace/workspace/$BUILD_ENV-app-FCinfo.txt)"
        export FCINFO=`cat $repo_workspace/workspace/$BUILD_ENV-app-FCinfo.txt`
        echo "Git Pull Done"

        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Git Pull Done", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\nJob Name:*$JOB_NAME* initiated by *$BUILD_USER*\n*File Generation initiated* in $BUILD_ENV"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
            sleep 1

        #################################

        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\n"UAT_Deployment_Gulp"_"$BUILD_USER"\n*$FCINFO*"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
        curl -sH 'Content-Type: application/json' -X POST $DEV_GCHAT_URL --data '{"text": "'"Hi <users/all>\n"UAT_Deployment_Gulp"_"$BUILD_USER"\n*$FCINFO*"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
        sleep 1
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Job Name:$JOB_NAME\n*File Generation initiated*"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
        fi

        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Git Pull Done in '$BUILD_ENV', "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

        echo "git clone completed successfully"
        #====================================================================================================
                    echo "Going to do the Version incremental steps"
        #====================================================================================================
        #Files_Version_Increment_Create a dummy folder created in GCDN
            version_inc()
            {
            mkdir -p $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app
            mkdir -p $repo_workspace/workspace/profit-FC/profit_dist
                #version=$(ls -tr "$Destination" | tail -1) # Get the latest version
            export version=$(gsutil ls "$CDN_BUCKET"/ | grep -o "P2\.[0-9]\+\.[0-9]\+" | sort -V | tail -n 1)
            sleep 2
            echo $version | grep "tar"
            ES=$?
                if [ $ES -eq 0 ]; then
                    echo "Compressed file is there. Contact sysops."
                    exit 1
                fi

                # Extract version components
                first_digit=$(echo "$version" | awk -F "." '{print $1}' | sed 's/P//') # Remove 'P' prefix
                middle_digit=$(echo "$version" | awk -F "." '{print $2}')
                last_digit=$(echo "$version" | awk -F "." '{print $3}')

                # Increment version logic
                if [[ $last_digit -eq 99 ]]; then
                    last_digit=1
                    middle_digit=$((middle_digit + 1))
                else
                    last_digit=$((last_digit + 1))
                fi

                if [[ $middle_digit -eq 100 ]]; then # Transition to new major version
                    middle_digit=0
                    first_digit=$((first_digit + 1))
                fi

                # Format the new version
                version="P${first_digit}.${middle_digit}.${last_digit}"
                echo "$version" > $repo_workspace/workspace/$BUILD_ENV-fc.txt
                echo "Updated version: $version"
                create_empty_CDN_version=$(gsutil cp -n /dev/null $CDN_BUCKET/$version/)
                check_empty_CDN_verion=$(gsutil ls "$CDN_BUCKET"/ | grep -o "P2\.[0-9]\+\.[0-9]\+" | sort -V | tail -n 1)
                echo "Empty folder created: $check_empty_CDN_verion"
                #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Empty Version '$check_empty_CDN_verion' Folder created in GCDN ", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

            }        
        ##########################################
        version_inc
        ############################################
        #==========================================================================================
                echo  "File copy generation is started"
        #==========================================================================================
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "File generation started in '$BUILD_ENV'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

        trap 'echo "Error: filescopy generation failed in '$BUILD_ENV'"; exit 1' ERR

        cd $repo_workspace/workspace/profit-FC/app-web/src/main/webapp/ng/
        rm -rf node_modules .angular

        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Generating Node Modules", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

            echo "Executing npm install"
            npm install --force || send_alert
	    npm install /u01/sfw/dhtml_9.0.1 --force || send_alert
	    npm i /u01/sfw/scheduler_7.1.0 --force || send_alert
	    npm install /u01/sfw/diagram_6.0.3_enterprise --force || send_alert

        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Node Module Generation Done", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null


        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Executing node command", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

        echo "Executing node command"
        #node --max-old-space-size=32768 'node_modules/@angular/cli/bin/ng' build --configuration production || send_alert
        #node --max-old-space-size=$RAM_MEMORY 'node_modules/@angular/cli/bin/ng' build --configuration production || send_alert
	node --max_old_space_size=$RAM_Memory './node_modules/@angular/cli/bin/ng' build --configuration=production || send_alert
	#node --max_old_space_size=$RAM_MEMORY ./node_modules/@angular/cli/bin/ng build --configuration=production --source-map=false --vendor-chunk=false --named-chunks=false --output-hashing=all --build-optimizer=true
 
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Executing gulp command", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null


        echo "Executing gulp command"
        gulp angularAll appAll styles || send_alert

        rm -rf node_modules .angular
  	
      	cd $repo_workspace/workspace/profit-FC/profit_dist/ng/
        rm -rf node_modules .angular
        

        echo "Filescopy generation completed successfully"
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "File generation Done in '*$BUILD_ENV*'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}'

        FC_END_TIME=`date +%s`
        RUNTIME=$((FC_END_TIME-FC_START_TIME))
        TOTAL_MINS=$((RUNTIME / 60))
        TOTAL_SEC=$((RUNTIME % 60))

        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Total Time taken for File generation  $TOTAL_MINS minutes $TOTAL_SEC seconds "'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

        sleep 2
        #====================================================================================================
                    echo "Going To Copy the file to jenkin-vm folder path"
        #====================================================================================================

        SOURCE_HOME=$repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app
        SVN_EXPORT_STATUS_FILE=$SOURCE_HOME/Profit-git-export-report.txt
        JOB_PATH=$repo_workspace/workspace
        Build_log=$JOB_PATH/$JOB_NAME/build_log.txt

        ng_build()
        {
        #rsync -avz $repo_workspace/workspace/profit-FC/app-web/src/main/webapp/ng $repo_workspace/workspace/profit-FC/profit_dist/.
        cp -rf $repo_workspace/workspace/profit-FC/app-web/src/main/webapp/ng $repo_workspace/workspace/profit-FC/profit_dist/.
        cp -rf $repo_workspace/workspace/profit-FC/app-web/src/main/webapp/ajs $repo_workspace/workspace/profit-FC/profit_dist/.


        cd $repo_workspace/workspace/profit-FC/profit_dist/ng/

        mkdir -p  $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version/app/ng/src/assets/css
        mkdir -p  $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version/app/ng/dist
        mkdir -p  $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version/app/ng/gulp
        mkdir -p  $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version/app/ng/src/assets/fonts
        mkdir -p  $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version/app/ng/src/assets/images
        mkdir -p  $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version/app/ajs/oauth2-login/dist
        }

        #version_inc #This function moved to top of the file generation function method.
        ng_build


        echo "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#"
        echo "New Version Number is $version"
        ES=$?
        echo "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#"
        if [ $ES == 0 ]
                then
        cp -r $JOB_PATH/profit-FC/profit_dist/ng/src/assets/css/* $JOB_PATH/profit-FC/Profit-Static-Content/web/app/$version/app/ng/src/assets/css/
        cp -r $JOB_PATH/profit-FC/profit_dist/ng/dist/*          $JOB_PATH/profit-FC/Profit-Static-Content/web/app/$version/app/ng/dist/
        cp -r $JOB_PATH/profit-FC/profit_dist/ng/gulp/*          $JOB_PATH/profit-FC/Profit-Static-Content/web/app/$version/app/ng/gulp/
        cp -r $JOB_PATH/profit-FC/profit_dist/ng/src/assets/fonts/* $JOB_PATH/profit-FC/Profit-Static-Content/web/app/$version/app/ng/src/assets/fonts/
        cp -r $JOB_PATH/profit-FC/profit_dist/ng/src/assets/images/* $JOB_PATH/profit-FC/Profit-Static-Content/web/app/$version/app/ng/src/assets/images/
        cp -r $JOB_PATH/profit-FC/profit_dist/ajs/oauth2-login/dist/* $JOB_PATH/profit-FC/Profit-Static-Content/web/app/$version/app/ajs/oauth2-login/dist/


        rsync -avz $repo_workspace/workspace/profit-FC/Profit-Static-Content/web/app/$version $Destination/.
        fi
	
	# Calculate the size of Files Copy Folder using du
	  export Files_Copy_Size=$(du -sh $Destination/$version | cut -f1)
	# Display the result
	  echo "FC Folder Size = $Files_Copy_Size"

        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"$JOB_NAME done in $BUILD_ENV version $version \nFC_Size=*$Files_Copy_Size* "'", "thread" : { { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
        #File Copy Generation is done.
        #====================================================================================================
                    echo "File Copy Generation is done Version: $version "
        #====================================================================================================
    }
 
#WAR Generation function 
Build_APP_WAR()
    {
        export GCP_WAR_THREAD=WAR-thread-$START_TIME
        export BUILDINFO=`cat $repo_workspace/workspace/$BUILD_ENV-app-buildinfo.txt`
        send_alert() {
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Hi '$BUILD_USER', \n'*$JOB_NAME*' \nMaven WAR Generation is Failed,\nPlease check", "thread" : { "threadKey": "THREAD-'$(date +%s)'"}}' >> /dev/null
    exit 1
        }

        ### Gchat update for Application WAR Generation###
        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\nJob Name: *$JOB_NAME* initiated by *$BUILD_USER*\n*Application WAR initiated* in $BUILD_ENV\n$BUILDINFO"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
        ####
        JOB_PATH=$repo_workspace/workspace/profit/

        if [ ! -d $JOB_PATH ]
                then
                        mkdir -p $JOB_PATH
                        mkdir -p $JOB_PATH/clean_source
                else
                        rm -rf $JOB_PATH/clean_source/*

        fi

        cd $JOB_PATH
        #################################
        GIT_PULL "UAT_Deployment_Maven" "Build" #Pull the data from Git
        Revision_Save_info "Build" # Save the Hashcode and CURRENT_BRANCH to Build info
        export BUILDINFO=`cat $repo_workspace/workspace/$BUILD_ENV-app-buildinfo.txt`
        
        #################################
        ### Gchat update for Application WAR Generation###
        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\n*Job Name: $JOB_NAME*\n*Application WAR initiated* in $BUILD_ENV"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\nUAT_Deployment_Maven_"$BUILD_USER",\n*$BUILDINFO*"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
        curl -sH 'Content-Type: application/json' -X POST $DEV_GCHAT_URL --data '{"text": "'"Hi <users/all>\nUAT_Deployment_Maven_"$BUILD_USER",\n*$BUILDINFO*"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
        sleep 1
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\nJob Name: $JOB_NAME,\n*Application WAR initiated* in $BUILD_ENV"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null

        ### To update the variables in the app.war/WEB-INF/classes/build-info.properties ###
        MVN_ENV_PROP_FILE="/var/tmp/$JOB_NAME-mvn-env.properties"

        MR_ID=$(git log -1 | grep "See merge request" | cut -d"!" -f2)
        if [ $MR_ID -gt 0 ]; then echo "MR_ID=$MR_ID"; else MR_ID=0; echo "MR_ID=$MR_ID"; fi

        COMMITS_COUNT=$(git log --oneline | wc -l)
        BUILD_ID="${COMMITS_COUNT}_${MR_ID}"
        TIME_STAMP=$(date +%Y%m%d-%H%M-%Z)

        echo "build_id=$BUILD_ID" > $MVN_ENV_PROP_FILE
        echo "build_time=$TIME_STAMP" >> $MVN_ENV_PROP_FILE
        ### To update the variables in the app.war/WEB-INF/classes/build-info.properties ###
        
        #Maven build going to start
        #====================================================================================================
                    echo "Maven build going to start"
        #====================================================================================================
       export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
       export PATH=$JAVA_HOME/bin:$PATH
       	/u01/sfw/apache-maven-3.6.3/bin/mvn clean install -U -DjavaVersion=17 -Dbranch_name=$CURRENT_BRANCH -Dcommit_hash=$REVISION -Dbuild_id=$build_id -Dbuild_time=$build_time || send_alert     
        export BUILDINFO=`cat $repo_workspace/workspace/$BUILD_ENV-app-buildinfo.txt`
        export H_WORKSPACE_HOME=$repo_workspace/workspace/profit
        export BUILD_DEPLOY_FOLDER=build/deploy
        export BUILD_FILENAME=app.war
        export DEPLOY_SOURCE="$H_WORKSPACE_HOME/app-web/target/app.war"
        export MD5SUM=`md5sum $DEPLOY_SOURCE | awk '{print $1}'`
	
	# Calculate the size of app.war using du
	  export Application_War_Size=$(du -sh $DEPLOY_SOURCE  | cut -f1)
	# Display the result
	  echo "app.war size = $Application_War_Size"

        #curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\n*Job Name: $JOB_NAME* \n*Application WAR generated* in $BUILD_ENV \n$BUILDINFO for $NAME \nmd5sum: *$MD5SUM* \napp.war = *$Application_War_Size* "'", "thread" : { "threadKey": "GCP_WAR_THREAD-'$(date +%s)'"}}' >> /dev/null
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi <users/all>\n*Job Name: $JOB_NAME* \n*Application WAR generated* in $BUILD_ENV for $NAME \nmd5sum: *$MD5SUM* \napp.war = *$Application_War_Size* "'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
        # Application WAR Generated is Done
        sleep 1
        #====================================================================================================
                    echo "Maven Application WAR Generated is Done"
        #====================================================================================================
    }
#Files_Copy_To_GCP_CDN_&_AWS_And_Switch_Method
Files_Copy_CDN ()
    {
            export GCP_CDN_THREAD=CDN-thread-$START_TIME
            export FILE_VERSION=$(cat $repo_workspace/workspace/$BUILD_ENV-fc.txt)
            export CDN_BUCKET=$CDN_BUCKET
            export CDN_URL=$CDN_URL
            export AWS_S3_BUCKET=$AWS_S3_BUCKET
            export AWS_S3_URL=$AWS_S3_URL
	    export BASE_PATH=/u01/CDN

        # After_FC_Node_Boucne paramater "yes" or "no"
            if [ $REQUIRED = "Files_Copy" ]; then
                    echo "$REQUIRED alone in $BUILD_ENV Env"
                        Cache_Clear="yes"
                elif [ $REQUIRED = 'Build_And_Files_Copy' ]; then
                    echo "$REQUIRED in $BUILD_ENV Env"
                        Cache_Clear="yes"  
                elif [ $REQUIRED = 'Files_Copy_And_Build' ]; then
                    echo "$REQUIRED in $BUILD_ENV Env"
                        Cache_Clear="yes"
                elif [ $REQUIRED = "Build" ]; then
                    echo "Deployment is done in $BUILD_ENV ENV"
                        Cache_Clear="no" 
                else
                    "ERROR: Invalid FC_VER_NOTIFY"
            fi
           export BASE_PATH=/u01/CDN

            echo "The updated version $FILE_VERSION coping to the $BASE_PATH"
            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Files Copy Initiated in '$BUILD_ENV' GCP CDN Bucket", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
            echo "The updated version $FILE_VERSION copied to the $BASE_PATH"
            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "The updated version '*$FILE_VERSION*' Coping to Staging GCP CDN Bucket", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
            echo "The updated version $FILE_VERSION coping to $BUILD_ENV GCP_CDN_BUCKET"
            sleep 2
           #Files Copy Latest Folder check in Base Path       
           
            START_TIME=$`date +%s`
            FILE_VERSION=$FILE_VERSION
            BASE_PATH=$BASE_PATH
            export CDN_BUCKET=$CDN_BUCKET
            export CDN_URL=$CDN_URL
            cd $BASE_PATH
            rm -rf P2.*
            scp -r /u01/jenkins/profit-FC/App/$FILE_VERSION $BASE_PATH/.
           
        echo " $(tput setaf 4) !!!!!!!!!!!!! WELCOME TO GOOGLE CLOUD PLATFORM ZONE !!!!!!!!!!!!! $(tput sgr 0)"

        echo " $(tput setaf 4) Copying the file version to GCP $(tput sgr 0)"
            gsutil -m cp -r -Z $BASE_PATH/$FILE_VERSION $CDN_BUCKET/
            gsutil -m setmeta -h "Cache-Control:max-age=2592001" $CDN_BUCKET/$FILE_VERSION/************
        echo " $(tput setaf 3) Copied the files to GCP, please verify this URL, '$CDN_URL/$FILE_VERSION/app/ng/src/assets/css/bootstrap.css' $(tput sgr 0)"

        ESTATUS=$?
         if [ $ESTATUS -eq 0 ]
            then
                echo "File is ready for live :)"
            else
                echo "OOPS!!!! There is an error in copying the file to GCP .. please check"
            exit $ESTATUS
         fi

            echo "########## Deleting the old file version from GCP staging bucket ##########"

            folders=($(gsutil ls $CDN_BUCKET/ | grep "P2.*" | sort -rV))
    keep_count=400

        if [ "${#folders[@]}" -gt "$keep_count" ]; then
            for ((i = keep_count; i < ${#folders[@]}; i++)); do
                gsutil -m -q rm -r "${folders[i]}"
                echo "Deleted File Version: ${folders[i]}"
            done
          else
            echo "Only latest 400 files-copy versions available in the bucket"
        fi
            echo "Files copy the version *$FILE_VERSION* is Done in GCP CDN"
            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Files copy the version *$FILE_VERSION* is Done in GCP CDN"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

#AWS_Copying_method            
            echo "Going to copy the version *$FILE_VERSION* in AWS CDN"
            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Going to copy the version *$FILE_VERSION* in AWS CDN"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
    ##########
                START_TIME=$`date +%s`
            export FILE_VERSION=$FILE_VERSION
            export BASE_PATH=$BASE_PATH
                cd $BASE_PATH
                #rm -rf P2.* #no need here we are enabled folder maintan method
                scp -r /u01/jenkins/profit-FC/App/$FILE_VERSION $BASE_PATH/.
                send_alert() {
                    curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Hi QA TEAM, \n'*$JOB_NAME*' AWS FC copy is Failed, Please check", "thread" : { "threadKey": "THREAD-'$(date +%s)'"}}' >> /dev/null
                    exit 1
                }
                echo "The updated $FILE_VERSION going to copy to the AWS S3 buckets"

                sleep 5

            echo " $ !!!!!!!!!!!!! WELCOME TO AWS CLOUD PLATFORM ZONE !!!!!!!!!!!!! $"
            echo " $ Copying the file version to AWS S3 $"

            for i in $(find $FILE_VERSION -name "*.js" -size +9M);
            do
                    gzip $i;
                    mv $i.gz $i;
                    aws s3 cp $i $AWS_S3_BUCKET/$i --content-encoding gzip ;
                    rm $i;
            done || exit 1

            aws s3 cp $FILE_VERSION $AWS_S3_BUCKET/$FILE_VERSION --recursive || send_alert
            rm -rf $FILE_VERSION
            sleep 2
            echo " $Copied the files to AWS S3, please verify this URL, ''$AWS_S3_URL'/$FILE_VERSION/app/ng/src/assets/css/bootstrap.css' $"

            echo "########## Deleting the old file version from AWS Uat bucket ##########"

            folders=($(aws s3 ls $AWS_S3_BUCKET | grep "P2.*" | sort -rV | awk '{ print $2 }'))

            keep_count=400

        if [ "${#folders[@]}" -gt "$keep_count" ]; then
            for ((i = keep_count; i < ${#folders[@]}; i++)); do
                aws s3 rm $AWS_S3_BUCKET/"${folders[i]}" --recursive --quiet
                echo "Deleted File Version: ${folders[i]}"
            done
        else
            echo "Only latest 400 files-copy versions available in the bucket"
            fi

            echo "############################################################################"

            ########################
            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"The Files Copy version *$FILE_VERSION* is Done in AWS CDN"'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

            echo "The Latest Files copy Version $FILE_VERSION Successfully copied to the both GCP & AWS CDN BUCKETS"
            ##############################

            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"The Files copy  Version *$FILE_VERSION* succusfully copied to the both GCP AND AWS BUCKETS "'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null

            sleep 3

            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"The Latest Files copy Version *$FILE_VERSION* going to switch in UAT ES "'", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
            #################################
            echo "The Latest Files copy Version $FILE_VERSION going to switch in UAT ES"

#SWITCH_IN_ES_Steps
ssh us-stag-automation << EOF
            DATE=$DATE
            FILE_VERSION=$FILE_VERSION
            BASE_PATH=$BASE_PATH
            export CDN_BUCKET=$CDN_BUCKET
            export CDN_URL=$CDN_URL
            export AWS_S3_BUCKET=$AWS_S3_BUCKET
            export AWS_S3_URL=$AWS_S3_URL
            
        ######################
            echo "#~~~~~~~~~~~~~~~~~~~~~-----------------#"
            echo "# BEFORE UPDATE in $PROJECT ES Athena #"
            echo "#~~~~~~~~~~~~~~~~~~~~~-----------------#"
                    
            BEFORE_UPDATE_GCP=\$(curl -u 'elastic:Stagprofit1@3' -XGET --silent 'http://10.70.0.6:9104/378/_doc/11330?pretty=true' | grep value | awk '{print \$3}' | tail -1 | tr -d "," | tr -d '"')
            BEFORE_UPDATE_AWS=\$(curl -u 'elastic:Stagprofit1@3' -XGET --silent 'http://10.70.0.6:9104/378/_doc/7404?pretty=true' | grep value | awk '{print \$3}' | tail -1 | tr -d "," | tr -d '"')

            echo 'Profit Filescopy to GCP and AWS version switched in UAT ES'
            echo GCP CDN: "\$BEFORE_UPDATE_GCP"
            echo AWS CDN: "\$BEFORE_UPDATE_AWS"

            echo "#~-~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~-~~~#"
            echo "# UPDATING $FILE_VERSION IN UAT PROFIT AWS #"
            echo "#~~-~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#"
     
           curl -u 'elastic:Stagprofit1@3' -XPOST --silent 'http://10.70.0.6:9104/378/_doc/7404/_update?pretty' -H 'Content-Type: application/json' -d '{ "doc": {"value" : "'\$AWS_S3_URL'/'\$FILE_VERSION'"} }'

            echo "#~-~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#"
            echo "# UPDATING $FILE_VERSION IN UAT PROFIT GCP #"
            echo "#~~-~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~-~~#"
       
            curl -u 'elastic:Stagprofit1@3' -XPOST --silent 'http://10.70.0.6:9104/378/_doc/11330/_update?pretty' -H 'Content-Type: application/json' -d '{ "doc": {"value" : "'\$CDN_URL'/'\$FILE_VERSION'"} }'

            echo "#~------~~~~~~~~~~~~~~~~~~~~#"
            echo "# AFTER UPDATE in ES Athena #"
            echo "#~~~~~~~~~~~~~~~~~~~~~------#"
      sleep 2        
            AFTER_UPDATE_GCP=\$(curl -u 'elastic:Stagprofit1@3' -XGET --silent 'http://10.70.0.6:9104/378/_doc/11330?pretty=true' | grep value | awk '{print \$3}' | tail -1 | tr -d "," | tr -d '"')
            AFTER_UPDATE_AWS=\$(curl -u 'elastic:Stagprofit1@3' -XGET --silent 'http://10.70.0.6:9104/378/_doc/7404?pretty=true' | grep value | awk '{print \$3}' | tail -1 | tr -d "," | tr -d '"')

            echo 'Profit Filescopy to GCP and AWS version switched in UAT ES'
            echo GCP CDN: "\$AFTER_UPDATE_GCP"
            echo AWS CDN: "\$AFTER_UPDATE_AWS"
            exit 0
EOF
    
    #CDN_FILE_SIZE_CHECK
        #export CDN_FILE_SIZE=$(/u01/jenkins/scripts/pft_fn_Google_CDN_File_Size.sh "$BUILD_ENV" "GCP_CDN_BUCKET")
        export CDN_FILE_SIZE=$(/u01/jenkins/scripts/pft_fn_Google_CDN_File_Size_v2.sh "$BUILD_ENV" "GCP_CDN_BUCKET" "$repo_workspace")
        echo "$CDN_FILE_SIZE"
        sleep 2
    curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "The updated version '*$FILE_VERSION*' switched in '$BUILD_ENV' ES", "thread" : { "threadKey": "'"$FC_THREAD"'"}}' >> /dev/null
    sleep 2
#--------------------------- Cache_Clear------------------------------
    if [[ "$Cache_Clear" = "yes" ]];then
	    curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Going to Cache_Clear $BUILD_ENV APP nodes", "thread" : {"threadKey": "'"$GCP_CDN_THREAD"'"}}' >> /dev/null
	ssh us-stag-automation 'bash -s' < /u01/jenkins/scripts/jenkins_stag_and_UAT_node_Cache_Clear.sh US-APP-NODE
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"*Hi QA Team*,\nThe Latest Files copy Version *$FILE_VERSION* is switched in $BUILD_ENV Env,\n*GCP_CDN_File_Size*\nFC Version=*$FILE_VERSION*\n*$CDN_FILE_SIZE*,\nCache_Clear done,\nPlease *logout* and *login* then check the flow, \nAWS CDN: $AWS_S3_URL/$FILE_VERSION/app/ng/src/assets/css/bootstrap.css \nGCP CDN: $CDN_URL/$FILE_VERSION/app/ng/src/assets/css/bootstrap.css"'", "thread" : { "threadKey": "THREAD-'$(date +%s)'"}}' >> /dev/null

    else
	    echo "Files Copy done in $BUILD_ENV"
	    curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"*Hi QA Team*,\nFiles copy Version *$FILE_VERSION* is copied and switched in $BUILD_ENV Env,\n*GCP_CDN_File_Size*\nFC Version=*$FILE_VERSION*\n*$CDN_FILE_SIZE*,\n*Once the Deployment done FC will be refleceted*"'", "thread" : { "threadKey": "GCP_CDN_THREAD-'$(date +%s)'"}}' >> /dev/null

    fi
    sleep 2
##########################
keep_count=3
# Function to clean up folders in a given path
cleanup_folders() {
    local path="$1"
    if [ -d "$path" ]; then
        folders=($(ls "$path/" | grep "P2.*" | sort -rV))

        if [ "${#folders[@]}" -gt $keep_count ]; then
            for ((i = keep_count; i < ${#folders[@]}; i++)); do
                rm -rf "$path/${folders[i]}"
                echo "Deleted OLD FC Version: ${folders[i]} from $path"
            done
        else
            echo "Only the latest $keep_count file versions are available in $path."
        fi
    else
        echo "Directory $path does not exist."
    fi
}

# Run cleanup on both paths
cleanup_folders "$Destination"
cleanup_folders "$SOURCE_HOME"
sleep 2

    }
#Docker_Image_Generation_Function           
Docker_Image_Generation()
        {
        shopt -s extglob
        export GCP_Docker_THREAD=Docker-thread-$START_TIME
        send_alert() {
	    curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "*Docker Image generation Failed for '$NAME' Node*", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
            }

        # Trap any errors and call the send_alert function
            trap 'send_alert; exit 1' ERR

        #git pull command
            cd $repo_workspace/workspace/app-tomcat
            git fetch origin $TOMCAT_BRANCH
            git checkout $TOMCAT_BRANCH
            git pull origin $TOMCAT_BRANCH
        # Copy war file from WAR_LOC to webapps

            echo "1. Copying $WAR_NAME file to Profit $BUILD_ENV US region $NAME Node"
            echo "--------------------------------------------------------------------"
            echo -e "\n"

            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"*Hi QA Team*,\nGoing to Generate Docker Image using \n$BUILDINFO for $NAME Node"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null            
            #Source and Destination MD5SUM Copy and verify
            SRC_MD5SUM=`md5sum $SRC_WAR|awk '{print $1}'`
            cp -r $SRC_WAR $DEST
            DEST_MD5SUM=`md5sum $DEST_WAR|awk '{print $1}'`

        if [ "$SRC_MD5SUM" = "$DEST_MD5SUM" ]; then
            echo "================================================================================="
            echo "The MD5SUM is $DEST_MD5SUM and The MD5SUM of $WAR_NAME are the same"
            echo "================================================================================="
            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Md5sum of $WAR_NAME is $DEST_MD5SUM"'", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null

        else
            echo "################################################x"
            echo "The MD5SUM of $WAR_NAME isn't the same, please check"
            echo "################################################x" 
            exit 1;
        fi

        ssh -T gcp-stag@localhost << EOF
            shopt -s extglob
            NAME=$NAME
            STS=$STS
            JOB_NAME=$JOB_NAME
            BUILD_PATH=$BUILD_PATH
            WAR_NAME=$WAR_NAME
            PROJECT=$PROJECT
            GCR=$GCR
            ENV=$ENV
            GCHAT_URL=$GCHAT_URL
            #THREAD=$THREAD
            GCP_Docker_THREAD=$GCP_Docker_THREAD

            echo 0 >  "/tmp/\$ENV-\$STS-status"
        send_alert() {
            echo 1 > /tmp/\$ENV-\$STS-status
        }

        # Trap any errors and call the send_alert function
            trap 'send_alert; exit 1' ERR


        # Updating Image version 

            #echo "==================================="
            echo -e "\n"
            echo "1. Updating \$NAME Version"
            echo "------------------------------------"

            echo -e "\nDetecting older version\n"
        OLD_VERSION=\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --include-tags --format="value(tags[])" --sort-by=~UPDATE_TIME --limit=1)

        if [[ -z "\$OLD_VERSION" ]]; then
            echo -e "No Older Version is detected\n"
            echo -e  "Updating Newer Version"
            LATEST_IMAGE_VERSION="v1.0.0"
            echo \$LATEST_IMAGE_VERSION
            echo \$LATEST_IMAGE_VERSION > /tmp/\$ENV-\$STS-version
        else
            echo -e "Older Version is detected"
            echo \$OLD_VERSION
            echo -e "\nUpdating Newer Version"
            LATEST_IMAGE_VERSION=\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --include-tags --format="value(tags[])" --sort-by=~UPDATE_TIME --limit=1 | cut -d ";" -f2 | awk 'BEGIN{FIELDWIDTHS="2 10"}{print \$1}')\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --include-tags --format="value(tags[])" --sort-by=~UPDATE_TIME --limit=1 | cut -d ";" -f2 | awk 'BEGIN{FIELDWIDTHS="2 10"}{print \$2}' | awk 'BEGIN{FS=OFS="."} {\$3+=1;if    (\$3>99){\$2+=1;\$3=0};if(\$2>99) {\$1+=1;\$2=0}} 1')
            echo \$LATEST_IMAGE_VERSION > /tmp/\$ENV-\$STS-version
            export LATEST_IMAGE_VERSION=\$(cat /tmp/\$ENV-\$STS-version)
            echo \$(cat /tmp/\$ENV-\$STS-version)
        fi

        # Building Docker Images
            #echo "================================="
            echo -e "\n\n2. Building Latest Docker Image"
            echo "-----------------------------------------"
            echo -e "\n"

        curl -sH 'Content-Type: application/json' -X POST '$GCHAT_URL' --data '{"text": "Docker Image Generaion initiated for '$NAME' and image version is '$STS':'\$LATEST_IMAGE_VERSION'", "thread": { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null

            docker build -t \$GCR/\$PROJECT/\$ENV/\$STS:\$LATEST_IMAGE_VERSION \$BUILD_PATH -f \$BUILD_PATH/Dockerfile --pull || (send_alert && exit 1)
            IMAGE_NAME="\$GCR/\$PROJECT/\$ENV/\$STS:\$LATEST_IMAGE_VERSION"
            BUILD_VERSION=\$(docker images \$GCR/\$PROJECT/\$ENV/\$STS |  awk 'NR==2{print \$1":"\$2}')

        if [[ \$IMAGE_NAME == \$BUILD_VERSION ]];then
            echo -e "\n"
            echo "==================================="
            echo "Docker image build is done properly"
            echo "==================================="
            curl -sH 'Content-Type: application/json' -X POST '$GCHAT_URL' --data '{"text": "Docker image Generation Done for '$NAME' node", "thread": { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null
        else
            echo -e "\n"
            echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            echo "Docker images build is not done properly"
            echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 
            send_alert;
            exit 1;
        fi   
            #echo "===================================="
            echo -e "\n3. Pushing Latest Image into GCR"
            echo "---------------------------------------"
            echo -e "\n"

        DOCKER_SHA_SUM=\$(docker inspect --format='{{index .RepoDigests 0}}' \$GCR/\$PROJECT/\$ENV/\$STS:\$LATEST_IMAGE_VERSION | cut -d @ -f2)
        echo "\$GCR_SHA_SUM"
        echo "\$DOCKER_SHA_SUM"
        GCR_SHA_SUM=\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --sort-by=~UPDATE_TIME --format='value(version)' --limit=1)

        if [[ \$DOCKER_SHA_SUM == \$GCR_SHA_SUM ]];then
            echo -e "\n"
            echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            echo "This Image Version Alrady Pushed to GCR"
            echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            send_alert;
            exit 1;
        else
            echo -e "\n"
            echo "==============================================="
            echo "New Docker Image Version Detected !!!"
            echo "==============================================="
        fi

            docker push \$GCR/\$PROJECT/\$ENV/\$STS:\$LATEST_IMAGE_VERSION

            curl -sH 'Content-Type: application/json' -X POST '$GCHAT_URL' --data '{"text": "Docker Image '$STS':'\$LATEST_IMAGE_VERSION' pushed to Staging GCR", "thread": { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null

            SHA_SUM=\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --sort-by=~UPDATE_TIME --format='value(version)' --limit=1)

            curl -sH 'Content-Type: application/json' -X POST '$GCHAT_URL' --data '{"text": "sha256 of Docker Image '$STS':'\$LATEST_IMAGE_VERSION' is '\$SHA_SUM'", "thread": { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null


            GCR_IMAGE_VERSION=\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --include-tags --sort-by=~UPDATE_TIME --format="value(tags[])" --limit=1)

        if [[ \$GCR_IMAGE_VERSION == \$LATEST_IMAGE_VERSION ]];then
            echo -e "\n"
            echo "==============================================="
            echo "Image Version Matched. Image Upload Success!!!"
            echo "==============================================="
        else
            echo -e "\n"
            echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            echo "Image Version does not Match. Image Upload Failed"
            echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            send_alert;
            exit 1;
        fi

        echo -e "\n4. Adding Latest Tag for \$STS:\$LATEST_IMAGE_VERSION"
        echo "--------------------------------------------------------"
        echo -e "\n"
        gcloud artifacts docker tags delete \$GCR/\$PROJECT/\$ENV/\$STS:latest --quiet || (send_alert && exit 1)
        gcloud artifacts docker tags add \$GCR/\$PROJECT/\$ENV/\$STS:\${LATEST_IMAGE_VERSION}  \$GCR/\$PROJECT/\$ENV/\$STS:latest --quiet || (send_alert && exit 1)

        # echo -e "================================"
        echo -e "\n5. Deleting older Docker Images"
        echo -e "------------------------------------"
        echo -e "\n"

        DOCKER=\$(docker images \$GCR/\$PROJECT/\$ENV/\$STS | wc -l)

        if [[ \$DOCKER -gt 11 ]]; then
            docker rmi -f \$(docker images \$GCR/\$PROJECT/\$ENV/\$STS -q | tail -n \$(echo \$DOCKER -11 | bc)) ||(send_alert && exit 1)
            echo -e "\n older images deleted\n"
        else
            echo "Latest 10 Images Available";
        fi
            #echo -e "============================================================="
            echo -e "6. Removing older Docker Images in Google Container Registry"
            echo -e "-----------------------------------------------------------------"
            echo -e "\n"

        GCR1=\$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --limit=unlimited --sort-by=~UPDATE_TIME --format='value(version)' | wc -l)

        for digest in \$(gcloud artifacts docker images list \$GCR/\$PROJECT/\$ENV/\$STS --limit=unlimited --sort-by=~UPDATE_TIME --format='value(version)' | tail -n \$(echo \$GCR1 -50 | bc)); do

        if [[ \$GCR1 -gt 51 ]]; then
            gcloud artifacts docker images delete -q --delete-tags \$GCR/\$PROJECT/\$ENV/\$STS@\${digest}  || (send_alert && exit 1)
        else
            echo "Latest 50 Images Available";
        fi

        done
EOF
                echo `cat /tmp/$ENV-$STS-status`
            if [ `cat /tmp/$ENV-$STS-status` == 1 ]; then
                send_alert
                exit 1
            fi

                END_TIME=`date +%s`
                RUNTIME=$((END_TIME-START_TIME))
                TOTAL_MINS=$((RUNTIME / 60))
                TOTAL_SEC=$((RUNTIME % 60))
                LATEST_IMAGE_VERSION=`cat /tmp/$ENV-$STS-version`

            echo -e "\nTotal Time taken for $STS Build $TOTAL_MINS minutes $TOTAL_SEC seconds"

            curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "*Docker Image generation done for '$NAME' Node with '$STS':'$LATEST_IMAGE_VERSION'*", "thread" : { "threadKey": "'"$GCP_WAR_THREAD"'"}}' >> /dev/null

            echo "Docker Image generation completed successfully with $BUILDINFO for $NAME Node with '$STS':'$LATEST_IMAGE_VERSION'"
        }

#Deployment_Function
Deployment ()
{
    export local=$1
	export FILE_VERSION="$(cat $repo_workspace/workspace/$BUILD_ENV-fc.txt)"
    # FC_VERSION_NOTIFY paramater "yes" or "no"
        if [ $REQUIRED = "Files_Copy" ]; then
            echo "$REQUIRED alone in $BUILD_ENV Env"
                FC_VERSION_NOTIFY="yes"
        elif [ $REQUIRED = 'Build_And_Files_Copy' ]; then
            echo "$REQUIRED in $BUILD_ENV Env"
                FC_VERSION_NOTIFY="no"  
        elif [ $REQUIRED = 'Files_Copy_And_Build' ]; then
            echo "$REQUIRED in $BUILD_ENV Env"
                FC_VERSION_NOTIFY="yes"                
        elif [ $REQUIRED = "Build" ]; then
            echo "Deployment is done in $BUILD_ENV ENV"
               FC_VERSION_NOTIFY="no" 
        else
            "ERROR: Invalid FC_VER_NOTIFY"
        fi
    ## Uat_Node_Deployment_Steps 
    ssh gcp-stag@localhost -t ssh gcp-stag-build 'bash -sx' < /u01/jenkins/jenkins-scripts/stag_deployment_script/deploy_gchat.sh us us api $JOB_NAME UAT $FILE_VERSION $FC_VERSION_NOTIFY $REQUIRED $GCP_WAR_THREAD


}        
###########
    for i in $REQUIRED
        do
            # call your procedure/other scripts here below
            echo "$i"
            input=$i
            case $input in

            Files_Copy)
                #Files_Generation || send_alert
                #Files_Copy_CDN || send_alert
                    ;;
            Build)
                Build_APP_WAR || send_alert
                Docker_Image_Generation || send_alert
                Deployment "$GCP_WAR_THREAD"|| send_alert
                    ;;
            Build_And_Files_Copy)
                Build_APP_WAR || send_alert
                Docker_Image_Generation || send_alert
                Deployment "$GCP_WAR_THREAD" || send_alert
                #Files_Generation || send_alert
                #Files_Copy_CDN || send_alert
                    ;;
            Files_Copy_And_Build)
                #Files_Generation || send_alert
                #Files_Copy_CDN || send_alert
                #Build_APP_WAR || send_alert
                #Docker_Image_Generation || send_alert
                #Deployment "$GCP_WAR_THREAD" || send_alert
                    ;;                                
            *)
                echo "Err... Please select the build or Files copy request" 
                curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "Hi '$BUILD_USER',\n*Please select appropriate Build and FC*", "thread" : { "threadKey": "THREAD-'$(date +%s)'"}}' >> /dev/null
                exit 1
                    ;;
        esac
    done
else 
        echo "################# Arguments are missing please confirm the arguments ####################"
        curl -sH 'Content-Type: application/json' -X POST $GCHAT_URL --data '{"text": "'"Hi '$BUILD_USER',\n*$JOB_NAME* in $BUILD_ENV\n*Input Arguments are missing* please check the input arguments"'", "thread" : { "threadKey": "'"$GCP_THREAD"'"}}' >> /dev/null
        exit 1
fi
##### END #####
