#!/usr/bin/env bash
# inspired by https://github.com/Originate/guide/blob/master/android/guide/Continuous%20Integration.md

function envSetup {
    #sudo apt-get update
    #sudo apt-get install libqt5widgets5
    sudo npm install -g shelljs@0.7.0
    sudo npm install -g cordova@8.0.0
    cordova telemetry off

    ./install.sh
    #./gradlew androidDependencies

    gem install bundler
    gem install danger
    gem install danger-junit
    gem install danger-android_lint
    gem install danger-jacoco
}

function printTestsToRun {
    if [ -n "$NIGHTLY_TEST" ]; then
        echo -e "\n\nNightly -> Run everything."

    # Check branch name since PR env vars are not present on manual re-runs.
    elif [[ $CIRCLE_BRANCH == *"pull"* ]]; then
        LIBS_TO_TEST=$(ruby .circleci/gitChangedLibs.rb)
        echo -e "export LIBS_TO_TEST=${LIBS_TO_TEST}" >> "${BASH_ENV}"
        if [[ ! -z ${LIBS_TO_TEST} ]]; then
            echo -e "\n\nLibraries to Test-> ${LIBS_TO_TEST//","/", "}."

            # Check if this is a test job that should continue
            #if [[ -z ${CURRENT_LIB} ]] && [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]]; then
            #    circleci step halt
            #fi
        else
            echo -e "\n\nNothing to Test."
            #circleci step halt
        fi
    else
        echo -e "\n\nNot a PR -> skip tests."
        #circleci step halt
    fi
}

function runTests {
    if ([ -n "$CIRCLE_PULL_REQUEST" ]); then
        android_api=27
    else
        # Run API 21 on Mon, 23 on Wed, 25 on Fri
        android_api=$((20 + $(date +"%u")))      
    fi

    [[ $android_api < 23 ]] && device="Nexus6" || device="NexusLowRes"
    gcloud firebase test android run \
        --project mobile-apps-firebase-test \
        --type instrumentation \
        --app "native/NativeSampleApps/RestExplorer/build/outputs/apk/debug/RestExplorer-debug.apk" \
        --test ${TEST_APK}  \
        --device model=$device,version=$android_api,locale=en,orientation=portrait  \
        --environment-variables coverage=true,coverageFile="/sdcard/coverage.ec"  \
        --directories-to-pull=/sdcard  \
        --results-dir=${CURRENT_LIB}-${CIRCLE_BUILD_NUM}  \
        --results-history-name=${CURRENT_LIB}  \
        --timeout 15m
}

function runDanger {
    #if [[ $CIRCLE_BRANCH == *"pull"* ]]; then
        if [ -z "${CURRENT_LIB}" ]; then
            export DANGER_GITHUB_API_TOKEN="5d42eadf98c58c9c4f607fcfc72cee4c7ef1486b" 
            danger --dangerfile=.circleci/Dangerfile_PR.rb --danger_id=PR-Check --verbose
        else
            if ls libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/*.xml 1> /dev/null 2>&1; then
                mv libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/*.xml libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/test-results.xml
            fi
            export DANGER_GITHUB_API_TOKEN="5d42eadf98c58c9c4f607fcfc72cee4c7ef1486b" 
            danger --dangerfile=.circleci/Dangerfile_Lib.rb --danger_id="${CURRENT_LIB}" --verbose
        fi
    #else
    #    echo "No need to run Danger."
    #fi
}