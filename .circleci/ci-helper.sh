#!/usr/bin/env bash
# inspired by https://github.com/Originate/guide/blob/master/android/guide/Continuous%20Integration.md

function envSetup {
    sudo apt-get update
    sudo apt-get install libqt5widgets5
    sudo npm install -g shelljs@0.7.0
    sudo npm install -g cordova@8.0.0
    cordova telemetry off

    ./install.sh
    ./gradlew androidDependencies

    gem install bundler
    gem install danger
    gem install danger-junit
    gem install danger-android_lint
    gem install danger-jacoco
}

function printTestsToRun {
    if [ -n "$NIGHTLY_TEST" ]; then
        echo -e "\n\nNightly -> Run everything."
    elif [ -n "$CIRCLE_PULL_REQUEST" ]; then
        LIBS_TO_TEST=$(ruby .circleci/gitChangedLibs.rb)
        echo -e "export LIBS_TO_TEST=${LIBS_TO_TEST}" >> "${BASH_ENV}"
        if [[ ! -z ${LIBS_TO_TEST} ]]; then
            echo -e "\n\nLibraries to Test-> ${LIBS_TO_TEST//","/", "}."
        else
            echo -e "\n\nNothing to Test."
        fi
    else
        echo -e "\n\nNot a PR -> skip tests."
    fi
}

function runTests {
    if ([ -n "$NIGHTLY_TEST" ] || ([ -n "$CIRCLE_PULL_REQUEST" ] && [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]])); then
        gcloud firebase test android run \
            --project mobile-apps-firebase-test \
            --type instrumentation \
            --app "native/NativeSampleApps/RestExplorer/build/outputs/apk/debug/RestExplorer-debug.apk" \
            --test ${TEST_APK}  \
            --device model=NexusLowRes,version=${ANDROID_API},locale=en,orientation=portrait  \
            --environment-variables coverage=true,coverageFile=/sdcard/tmp/code-coverage/connected/coverage.ec  \
            --directories-to-pull=/sdcard/tmp  \
            --results-dir=${CURRENT_LIB}-${CIRCLE_BUILD_NUM}  \
            --results-history-name=`echo ${CURRENT_LIB}`  \
            --timeout 15m

        mkdir -p firebase/results
        gsutil -m cp -r -U "`gsutil ls gs://test-lab-w87i9sz6q175u-kwp8ium6js0zw/${CURRENT_LIB}-${CIRCLE_BUILD_NUM} | tail -1`*" ./firebase/
        mv firebase/test_result_1.xml firebase/results
    else
        echo "No need to run ${CURRENT_LIB} tests for this PR."
    fi
}

function runDanger {
    if [ -n "$CIRCLE_PULL_REQUEST" ] && [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]]; then
        if [ -z "${CURRENT_LIB}" ]; then
            DANGER_GITHUB_API_TOKEN="5d42eadf98c58c9c4f60""7fcfc72cee4c7ef1486b" danger --dangerfile=.circleci/Dangerfile_PR.rb --danger_id=PR-Check --verbose
        else
            if ls libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/*.xml 1> /dev/null 2>&1; then
                mv libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/*.xml libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/test-results.xml
            fi
            DANGER_GITHUB_API_TOKEN="5d42eadf98c58c9c4f60""7fcfc72cee4c7ef1486b" danger --dangerfile=.circleci/Dangerfile_Lib.rb --danger_id="${CURRENT_LIB}" --verbose
        fi
    else
        echo "No need to run Danger."
    fi
}