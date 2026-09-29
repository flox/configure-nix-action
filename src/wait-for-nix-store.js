const exec = require('@actions/exec')

async function waitForNixStore() {
  let exitCode
  for (let attempt = 1; attempt <= 10; attempt++) {
    exitCode = await exec.exec(
      'nix',
      ['store', 'ping', '--extra-experimental-features', 'nix-command'],
      { ignoreReturnCode: true }
    )
    if (exitCode === 0) return
    if (attempt < 10) {
      await new Promise(resolve => setTimeout(resolve, 1000))
    }
  }
  throw new Error(
    `Nix store did not become ready after 10 attempts (last exit code: ${exitCode})`
  )
}

module.exports = waitForNixStore
