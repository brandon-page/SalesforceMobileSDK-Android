#!/usr/bin/env bash
# inspired by https://github.com/Originate/guide/blob/master/android/guide/Continuous%20Integration.md

function envSetup {
    sudo apt-get update
    sudo apt-get install libqt5widgets5
    sudo npm install -g shelljs@0.7.0
    sudo npm install -g cordova@7.0.0
    cordova telemetry off

    ./install.sh
    ./gradlew androidDependencies -PdisablePreDex

    gem install bundler
    gem install danger
    gem install danger-junit
    gem install danger-android_lint
    gem install danger-jacoco
}

function printTestsToRun {
    if [ -z "$CIRCLE_PULL_REQUEST" ]; then
        echo "Not a PR.  Run everything"
    else
        LIBS_TO_TEST=$(ruby .circleci/gitChangedLibs.rb)
        echo -e "export LIBS_TO_TEST=${LIBS_TO_TEST}" >> "${BASH_ENV}"
        if [[ ! -z ${LIBS_TO_TEST} ]]; then
            echo -e "\n\nLibraries to Test-> ${LIBS_TO_TEST//","/", "}."
        else
            echo -e "\n\nNothing to Test."
        fi
    fi
}

function startAVD {
    export LD_LIBRARY_PATH=${ANDROID_HOME}/emulator/lib64:${ANDROID_HOME}/emulator/lib64/qt/lib

    # This indicates a nightly build and what API version to test
    if [ -z "$AVD" ]; then
        if [ -z "$CIRCLE_PULL_REQUEST" ] || [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]]; then
            echo "y" | sdkmanager "system-images;android-22;default;armeabi-v7a"
            echo "no" | avdmanager create avd -n test22 -k "system-images;android-22;default;armeabi-v7a"
            emulator64-arm -avd test22 -noaudio -no-window -accel on
        else
            echo "No need to start an emulator to test ${CURRENT_LIB} for this PR."
        fi
    else
        echo "y" | sdkmanager "system-images;android-24;default;arm64-v8a"
        echo "no" | avdmanager create avd -n test24 -k "system-images;android-24;default;arm64-v8a"
        emulator -avd "$AVD" -no-audio -no-window -accel on
    fi
}

function waitForAVD {
    set +e

    if [ -z "$CIRCLE_PULL_REQUEST" ] || [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]]; then
        local bootanim=""
        export PATH=$(dirname $(dirname $(which android)))/platform-tools:$PATH
        until [[ "$bootanim" =~ "stopped" ]]; do
            sleep 5
            bootanim=$(adb -e shell getprop init.svc.bootanim 2>&1)
            echo "emulator status=$bootanim"
        done
        sleep 30
        # unlock the emulator screen
        adb shell input keyevent 82
        echo "Device Booted"
    else
        echo "No need to start an emulator to test ${CURRENT_LIB} for this PR."
    fi
}

function runTests {
    if [ -z "$CIRCLE_PULL_REQUEST" ] || [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]]; then
        if [[ "${CURRENT_LIB}" == "SalesforceReact" ]]; then
            ./gradlew :libs:SalesforceReact:assemble
        else
            if [[ "${CURRENT_LIB}" == "RestExplorer" ]]; then
                ./gradlew :native:NativeSampleApps:${CURRENT_LIB}:connectedAndroidTest --continue --no-daemon --max-workers 2 --stacktrace
            else
                ./gradlew :libs:${CURRENT_LIB}:connectedAndroidTest --continue --no-daemon  --max-workers 2 --stacktrace
            fi
        fi
    else
        echo "No need to run ${CURRENT_LIB} tests for this PR."
    fi
}

function runDanger {
    if [ -n "$CIRCLE_PULL_REQUEST" ] && [[ ${LIBS_TO_TEST} == *"${CURRENT_LIB}"* ]]; then
        if [ -z "${CURRENT_LIB}" ]; then
            DANGER_GITHUB_API_TOKEN="c21349d8a97e1bf9cdd9""301fd949a83db862216b" danger --dangerfile=.circleci/Dangerfile_PR.rb --danger_id=PR-Check --verbose
        else
            if ls libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/*.xml 1> /dev/null 2>&1; then
                mv libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/*.xml libs/"${CURRENT_LIB}"/build/outputs/androidTest-results/connected/test-results.xml
            fi
            DANGER_GITHUB_API_TOKEN="c21349d8a97e1bf9cdd9""301fd949a83db862216b" danger --dangerfile=.circleci/Dangerfile_Lib.rb --danger_id="${CURRENT_LIB}" --verbose
        fi
    else
        echo "No need to run Danger."
    fi
}