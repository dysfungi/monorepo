# monorepo

[![CI Workflow][ci-workflow-badge]][ci-workflow]

## organization

This repository is a [monorepo][awesome-monorepo] (not monolith) of my
programs using a
[hybrid approach](https://www.rocketpoweredjetpants.com/2017/11/organising-a-monorepo/#blended-monorepos)
of organization where the first level groups projects under the language
they are primarily written in (e.g., fsharp, python, terraform) and the
second is the functional area the projects are categorized as (e.g.,
api, infrastructure).

```
fsharp/api/automate/
terraform/infrastructure/frankenstructure
```

[awesome-monorepo]: https://github.com/korfuri/awesome-monorepo?tab=readme-ov-file
[ci-workflow-badge]: https://github.com/defrank/monorepo/actions/workflows/ci.yaml/badge.svg
[ci-workflow]: https://github.com/defrank/monorepo/actions/workflows/ci.yaml
