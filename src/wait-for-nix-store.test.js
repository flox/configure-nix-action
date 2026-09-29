const exec = require('@actions/exec')
const waitForNixStore = require('./wait-for-nix-store')

jest.mock('@actions/exec')

describe('waitForNixStore', () => {
  beforeEach(() => {
    jest.useFakeTimers()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('retries a failed ping until the daemon is ready', async () => {
    exec.exec.mockResolvedValueOnce(1).mockResolvedValueOnce(0)

    const ready = waitForNixStore()
    await jest.runAllTimersAsync()
    await ready

    expect(exec.exec).toHaveBeenCalledTimes(2)
    expect(exec.exec).toHaveBeenCalledWith(
      'nix',
      ['store', 'ping', '--extra-experimental-features', 'nix-command'],
      { ignoreReturnCode: true }
    )
  })

  it('fails after a bounded number of unsuccessful pings', async () => {
    exec.exec.mockResolvedValue(1)

    const ready = waitForNixStore()
    const failure = expect(ready).rejects.toThrow(
      'Nix store did not become ready after 10 attempts (last exit code: 1)'
    )
    await jest.runAllTimersAsync()
    await failure

    expect(exec.exec).toHaveBeenCalledTimes(10)
  })
})
