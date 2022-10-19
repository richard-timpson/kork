package com.salesforce.spinnaker.helper

import org.gradle.api.GradleScriptException

import java.io.InputStream

/**
 * class for static command utilities
 */
class CommandUtil {

  /**
   * Execute a list of commands, waiting for each to complete before executing
   * the next.  Ignore output.
   *
   * @param commandList the commands to execute
   * @param workingDir the working directory
   */
  static void executeCommands(List<List<String>> commandList, File workingDir) {

    println("command list is of type " + commandList.getClass())
    println("working dir is of type " + workingDir.getClass())
    commandList.each { command ->
      executeOneCommand(command, workingDir)
    }
  }

  /**
   * Execute one shell command and wait for it to complete.
   *
   * @param command the command to execute
   * @param workingDir the working directory
   * @param extraEnv a map of environment variable names and values to add to
   *     the environment when executing the command
   * @param timeoutMsec the number of milliseconds to wait
   * @param ignoreFailure assert that the exit value is 0 unless ignoreFailure is true
   *
   * @return stdout from the command
   */
  static String executeOneCommand(List<String> command,
                                  File workingDir,
                                  Map<String, String> extraEnv = null,
                                  int timeoutMsec = 5000,
                                  boolean ignoreFailure = false) {
    def process = executeBackgroundCommand(command, workingDir, extraEnv)
    return waitForProcess(command, process, timeoutMsec, ignoreFailure)
  }

  /**
   * Execute a command.  Return immediately -- do not wait for the command to complete.
   *
   * @param command the command to execute
   * @param workingDir the working directory
   * @param extraEnv a map of environment variable names and values to add to
   *     the environment when executing the command
   *
   * @return the resulting process
   */
  static Process executeBackgroundCommand(List<String> command,
                                          File workingDir,
                                          Map<String, String> extraEnv = null) {
    println "$command executing in $workingDir"

    if (extraEnv == null) {
      return command.execute(null, workingDir)
    }

    ProcessBuilder processBuilder = new ProcessBuilder(command)
    Map<String, String> env = processBuilder.environment()
    env.putAll(extraEnv);

    return processBuilder.directory(workingDir).start()
  }

  /**
   * Wait for a process to exit, capturing its output.
   *
   * @param command the command that initiated the process (for logging)
   * @param process the process to wait for
   * @param timeoutMsec the number of milliseconds to wait
   * @param ignoreFailure assert that the exit value is 0 unless ignoreFailure is true
   *
   * @return stdout from the command
   */
  static String waitForProcess(List<String> command, Process process, int timeoutMsec = 5000, boolean ignoreFailure = false) {

    // Groovy process handling offers us a number of options, all with some disadvantages. For more info:
    //    http://docs.groovy-lang.org/latest/html/gapi/org/codehaus/groovy/runtime/ProcessGroovyMethods.html
    //
    // The main options are:
    // 1) call consumeProcessOutput(), then call process.waitForOrKill(). consumeProcessOutput() starts two threads,
    //    which run in parallel with your main thread, taking process output and putting it where you specified. The
    //    downside here is you don't have access to those threads, so there's a potential state where waitForOrKill()
    //    has returned but the output consumer thread hasn't consumed all the output yet.  This can cause
    //    intermittent test failures. (Plus, those threads are never joined or cleaned up - ugly!)
    // 2) call waitForProcessOutput(). waitForProcessOutput() also starts two threads, but then it waits for the
    //    process to finish, waits for the output consumer threads to finish consuming output, and joins the output
    //    consuming threads. Trouble is, there's no way to specify a timeout.
    // 3) call waitForOrKill(), then just address the process' "inputStream" and "errorStream" variables and read the
    //    content from there yourself. Downside: if your process has more output than fits in a buffer, you will
    //    lose it.
    // 4) write your own code that implements waitForProcessOutput with a timeout
    //
    // For our use case here, 3) is the best fit. The race condition in 1) happens frequently enough that it causes
    // intermittent job failures. We frequently have commands that freeze, so a time out is required. We don't
    // require a lot of output from our commands. Though: if we DID have a need for a command with output that overran
    // the input stream buffers, we'd need to implement 4).
    long startTimeNano = System.nanoTime()
    process.waitForOrKill(timeoutMsec)
    long elapsedMsec = (System.nanoTime() - startTimeNano) / (1000 * 1000)
    def stdOut = inputStreamToString(process.inputStream)
    def stdErr = inputStreamToString(process.errorStream)
    def rc = process.exitValue()
    println "process $command complete (rc: $rc, elapsedMsec: $elapsedMsec, stdOut: ${stdOut.length()} char(s), stdErr: ${stdErr.length()} char(s))"
    stdOut.eachLine { println("OUT: $it") }
    stdErr.eachLine { println("ERR: $it") }
    if (!ignoreFailure && (rc != 0)) {
      throw new GradleScriptException("$command failed (rc: $rc)", null /* cause */)
    }
    return stdOut.toString()
  }

  private static String inputStreamToString(InputStream stream) {
    try {
      return stream.text
    } catch (IOException e) {
      // The process we're executing may close its output stream / our input
      // stream.  That's ok.
      if (e.message == "Stream closed") {
        return ""
      }
      throw e
    }
  }
}
