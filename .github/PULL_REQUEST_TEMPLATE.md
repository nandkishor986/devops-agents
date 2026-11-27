<!-- Follow the standard procedure in CONTRIBUTING.md: issue → fork → branch → signed-off commits → PR. -->
Closes #

## What and why

## How I verified it
- [ ] `python -m unittest discover -s tests` passes
- [ ] `claude plugin validate .` passes
- [ ] Real run or eval (describe):

## Checklist
- [ ] Branch from latest `main`, named `feat/…`, `fix/…`, `docs/…`, `security/…` or `rule/…`
- [ ] Conventional Commit messages, every commit signed off (`git commit -s`)
- [ ] No secrets, IDs, IPs, hostnames or company data in code, fixtures, evals, `learned.md` or skills
- [ ] Agent/SKILL files still < 120 lines
- [ ] Version bumped (if plugin files changed) and `CHANGELOG.md` updated
