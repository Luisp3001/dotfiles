import Quickshell

ShellRoot {
    Component.onCompleted: {
        console.log("HOME via function: " + Quickshell.env("HOME"))
        console.log("HOME via property: " + Quickshell.env.HOME)
        Quickshell.exit(0)
    }
}
