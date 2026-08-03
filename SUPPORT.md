# Support

Use the repository's public channels according to the type of request:

- GitHub Issues for reproducible bugs and scoped feature requests.
- GitHub Discussions for setup questions, usage questions, and design ideas.
- GitHub Private Vulnerability Reporting for suspected security issues after
  that feature is enabled on the public repository.

Include the Lerro version and build, macOS version, Mac architecture, signing
mode, relevant feature, expected result, observed result, and minimal
reproduction steps. Attach logs only after reviewing them for personal data.
Use synthetic text in screenshots and examples.

Release support covers the current stable release and the current development
branch. Older releases may receive a focused security fix when maintainers can
reproduce the issue and the affected code remains supportable.

System-level behavior still requires verification on the affected Mac. Useful
examples include TCC permission state, microphone hardware, Speech resources,
Accessibility behavior in a specific editor, global shortcut behavior, multiple
displays, and Gatekeeper. Maintainers may ask for a fresh run of the documented
diagnostic commands.

For security-sensitive reports, follow [SECURITY.md](SECURITY.md) and keep the
details out of public issues.
