const core = require('@actions/core')
const path = require('path')
const which = require('which')
const md5 = require('md5')

const ghWorkflowHash = md5(process.env.GITHUB_WORKFLOW_REF)
const ghRunnerHash = md5(
  process.env.RUNNER_NAME + process.env.RUNNER_OS + process.env.RUNNER_ARCH
)
const ghJobId = process.env.GITHUB_JOB

export const GH_CACHE_KEY = `nix-cache-${ghWorkflowHash}-${ghRunnerHash}-${ghJobId}`

export const GH_CACHE_PATHS = ['~/.cache/nix']
export const GH_CACHE_RESTORE_KEYS = [
  `nix-cache-${ghWorkflowHash}-${ghRunnerHash}-`,
  `nix-cache-${ghWorkflowHash}-`,
  'nix-cache-'
]

export function scriptPath(name) {
  return path.join(__dirname, '..', 'scripts', name)
}

export const SCRIPTS = {
  configureSubstituter: scriptPath('configure-substituter.sh'),
  configureAWS: scriptPath('configure-aws.sh'),
  configureGit: scriptPath('configure-git.sh'),
  configureGithub: scriptPath('configure-github.sh'),
  configureSsh: scriptPath('configure-ssh.sh'),
  recordNixStorePaths: scriptPath('record-nix-store-paths.sh'),
  pushNewNixStorePaths: scriptPath('push-new-nix-store-paths.sh'),
  restartNixDaemon: scriptPath('restart-nix-daemon.sh'),
  configureBuilders: scriptPath('configure-builders.sh'),
  configurePostBuildHook: scriptPath('configure-post-build-hook.sh')
}

export function exportVariableFromInput(input, defaultValue = '') {
  const name = `INPUT_${input.toUpperCase().replaceAll('-', '_')}`
  const value = core.getInput(input) || defaultValue
  core.debug(`Exporting variable ${name} to '${value}'`)
  core.exportVariable(name, value)
  return value
}
