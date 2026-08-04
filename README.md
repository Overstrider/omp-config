# OMP config

Este repositório é diretamente a raiz de configuração do
[Oh My Pi](https://github.com/can1357/oh-my-pi). Não existe plugin intermediário
nem sincronização de arquivos. A localização do clone é irrelevante: todos os
caminhos são resolvidos em tempo de instalação.

O instalador cria somente um alias no diretório home:

```text
<home>/.omp  ->  <clone>
```

`PI_CODING_AGENT_DIR` é calculado como `<clone>/agent`. O OMP lê e grava
diretamente nesta árvore:

```text
agent/
  config.yml
  mcp.json
  skills/
  agents/
  commands/
  extensions/
  rules/
  prompts/
  tools/
  hooks/
plugins/
  package.json
```

## O que este clone entrega

O repositório agora contém o pacote completo usado nesta instalação:

- fork Kimi K3/Merlin 9Router fixado por commit;
- correções anteriores de Cursor, replay, cache e HTTP/2 presentes no fork;
- patch local versionado para retomar Grok após `NGHTTP2_INTERNAL_ERROR`,
  `Provider stream stalled` e streams incompletos sem repetir tool calls;
- correção da descoberta de modelos para Merlin aparecer em `/model` e
  `/models` antes de o escopo da sessão ser congelado;
- timeout global de 15 segundos para perguntas de qualquer LLM, inclusive em
  Plan mode, escolhendo `recommended` automaticamente quando o modo interativo
  for habilitado;
- modo autônomo padrão sem perguntas: o tool `ask` não é exposto ao Grok;
- Pantheon incorporado, com agents, commands, skills, hooks e EvalFly;
- configuração Merlin/Cursor/Kimi, `/easy`, MCPs e skills versionadas.

O código do fork não é duplicado como um executável de 160+ MB no Git. O
[`fork/manifest.json`](fork/manifest.json) fixa a origem e o commit, enquanto
[`fork/patches/oh-my-pi-runtime-fixes.patch`](fork/patches/oh-my-pi-runtime-fixes.patch)
carrega os fixes mais recentes e seus testes. O instalador verifica hashes,
aplica o patch, testa, compila e instala um binário endereçado pelo conteúdo.
Ele também executa `bun audit` no fork, no agente e nos plugins e falha de
forma fechada se o catálogo atual reportar alguma vulnerabilidade.

## Ativar

Pré-requisitos: Git, Bun e PowerShell. No Windows, Windows PowerShell 5.1 ou
PowerShell 7 funcionam; no Linux, use PowerShell 7 (`pwsh`). Não é necessário
instalar `omp-fork` separadamente. A instalação usa a branch proprietária
[`feat/kimi-harness-merlin-9router`](https://github.com/Overstrider/oh-my-pi/tree/feat/kimi-harness-merlin-9router),
que contém o harness Kimi, as correções do provider Cursor e a proteção de
cache do Merlin. Esta configuração foi validada no commit
[`ba2eae3a0`](https://github.com/Overstrider/oh-my-pi/commit/ba2eae3a0),
mais o patch cujo SHA-256 está no manifesto. Depois de clonar, entre no
repositório sem depender de uma localização específica:

```powershell
git clone https://github.com/Overstrider/omp-config.git
Set-Location ./omp-config

$secret = Read-Host 'MERLIN_9ROUTER_API_KEY' -AsSecureString
$env:MERLIN_9ROUTER_API_KEY = [Net.NetworkCredential]::new('', $secret).Password
$env:MERLIN_9ROUTER_BASE_URL = Read-Host 'MERLIN_9ROUTER_BASE_URL'

./scripts/Install-OmpConfig.ps1
```

No Linux, execute os mesmos comandos dentro do `pwsh`. O instalador registra o
comando `omp` no perfil do PowerShell, mas não altera os perfis do Bash ou do
Zsh. A chave e o endpoint do router não são persistidos automaticamente no
Linux: cada sessão que iniciar o OMP precisa recebê-los pelo ambiente,
idealmente por um gerenciador de segredos. No Windows, o instalador migra esses
valores para um arquivo protegido pelo DPAPI e vinculado ao usuário atual; não
os mantém como variáveis persistentes em texto simples.

Compatibilidade validada em máquina limpa:

- Windows x64 com Windows PowerShell e Bun;
- Ubuntu 24.04 x64 com PowerShell 7.6 e Bun;
- reinstalação idempotente nas duas plataformas.

Os caminhos `arm64` existem no instalador, mas não foram executados em hardware
ARM nesta auditoria.

`Install-OmpConfig.ps1` chama automaticamente `Install-OmpFork.ps1`. Na
primeira execução ele clona o commit fixado, aplica o patch, roda as suítes
relevantes e os checks de tipos/formatação, compila e instala o fork. Em
execuções seguintes, hashes válidos tornam esse passo idempotente. Para apenas
reconstruir ou auditar o runtime do fork:

```powershell
./scripts/Install-OmpFork.ps1 -ForceRebuild
```

Em um clone limpo, o instalador baixa o addon nativo oficial da mesma versão
(`@oh-my-pi/pi-natives-<plataforma>-<arquitetura>`), verifica o build final e
o incorpora ao executável. O parceiro não precisa instalar Bazel, Rust nem
copiar arquivos nativos desta máquina.

O endpoint e a chave ficam fora do Git. No Windows, um helper local lê o
conteúdo protegido pelo DPAPI; no Linux, ele lê somente o ambiente do processo.
O `agent/models.yml` contém apenas chamadas para esse helper e nunca recebe os
valores reais. O OMP continua funcionando em CMD, PowerShell e terminais de IDE
sem colocar a chave ou o endpoint na linha de comando.
Depois execute:

```powershell
omp config path
omp --version
omp .
```

O primeiro comando deve apontar diretamente para
`<clone>/agent`. O instalador registra um launcher no perfil atual
do PowerShell. Ele garante que cada chamada use este clone e faz `omp .` abrir
na pasta atual, em vez de enviar `.` como mensagem ao modelo.

No Windows, o instalador também cria `omp.com` ao lado do `omp.exe`. Como
`.COM` tem precedência sobre `.EXE` no `PATHEXT`, CMD, pwsh, terminais de IDE e
chamadas diretas abrem o fork sem precisar encerrar processos antigos e sem
executar acidentalmente o upstream sem as correções de Cursor, Kimi e Merlin.
O launcher lê `run/omp-fork-runtime.json`, um ponteiro local ignorado pelo Git,
em vez de depender de caminhos ou nomes específicos da máquina original.

## Versionamento

- Alterações feitas por `omp config set` ou `/settings` aparecem diretamente
  em `agent/config.yml`.
- Skills, agentes, comandos, extensões, regras, prompts, ferramentas e hooks
  são arquivos normais dentro de `agent/`.
- `omp plugin install <pacote>@<versão>` atualiza
  `plugins/package.json` e `plugins/bun.lock`; ambos são versionados e o
  instalador restaura as dependências com lock estrito.
- MCP fica em `agent/mcp.json`.

## Modelos via Merlin 9router

O provider `merlin-9router` em `agent/models.yml` resolve o endpoint
OpenAI-compatible somente em runtime, sem versionar hostname ou rota.
`agent/config.yml` mantém os modelos principais nesse provider, desabilita
explicitamente o provider direto `openrouter` e desabilita o wizard de login
inicial. Todos os roles começam em
`merlin-9router/cx/gpt-5.6-luna:max`: `default`, `plan`, `slow`, `vision`,
`designer`, `commit`, `tiny`, `task`, `advisor` e `smol`. Cada role pode ser
alterado manualmente depois sem modificar os demais.

A discovery do Merlin usa `allowEmpty: false`: se o endpoint responder
temporariamente com um catálogo vazio, o fork preserva o último cache válido
em vez de fazer os modelos desaparecerem da interface.

A credencial e o endpoint nunca entram no Git. O helper valida HTTPS público,
recusa credenciais embutidas na URL, query, fragmento, IP literal e hostname
local/reservado. Para conferir o catálogo e o modelo padrão:

```powershell
omp models merlin-9router
omp -p --no-session 'Responda apenas: OK'
```

## Continuidade do Grok e perguntas automáticas

O runtime empacotado trata resets HTTP/2, stalls e encerramentos incompletos do
Cursor como interrupções retomáveis quando existe texto parcial ou uma tool
call local completa. Tool calls que o Cursor já marcou como executadas não são
repetidas. Casos ambíguos continuam falhando de forma explícita em vez de
arriscar duplicar efeitos colaterais.

`agent/config.yml` define `ask.enabled: false`, `ask.notify: off` e
`tools.approvalMode: yolo`. Assim, o Grok padrão não recebe o tool `ask`, não
abre seletores e resolve decisões reversíveis sozinho seguindo `agent/RULES.md`.

O timeout de 15 segundos continua configurado como fallback. Para reativar
perguntas deliberadamente, execute `omp config set ask.enabled true` e abra uma
nova sessão; ao expirar, a opção `recommended` é escolhida ou, sem recomendação,
a primeira opção. Para voltar ao modo autônomo:

```powershell
omp config set ask.enabled false
```

## Modos padrão

[Caveman](https://github.com/JuliusBrussee/caveman) e
[Ponytail](https://github.com/DietrichGebert/ponytail) estão instalados em
`agent/skills/` e iniciam em modo `full` em toda sessão. `agent/RULES.md`
mantém os comportamentos ativos desde a primeira resposta; os SHAs das versões
copiadas estão em `agent/skills/upstream-lock.json`.

## Comando `/easy`

`/easy` troca somente o modelo da sessão atual para o role oficial `smol`,
sem alterar o modelo principal. Para escolher o alvo, abra `/model`, entre em
**Roles**, selecione **smol** e atribua o modelo e o nível de raciocínio. O
comando aplica os dois valores imediatamente.

Use sem argumentos para apenas trocar o modelo, ou informe a tarefa na mesma
linha para trocar e executar imediatamente:

```text
/easy
/easy corrija o typo no README
```

O modelo continua ativo nessa sessão até outra seleção ser feita com
`/model`.

## OMP Pantheon

O [omp-pantheon](https://github.com/Agentic-Engineering-Agency/omp-pantheon)
fica incorporado diretamente em `agent/`, sem symlink para um clone externo.
Agents, commands, skills, hooks e a extensao `oh-my-omp` sao descobertos
automaticamente pelo OMP. A origem, versao e commit exatos ficam registrados
em `agent/pantheon/upstream-lock.json`; as dependencias de runtime ficam em
`agent/package.json` e `agent/bun.lock`.

O EvalFly permanece em modo advisory por padrao. Enforcement e hints so sao
ativados explicitamente dentro de cada projeto. No Windows, o nucleo em
TypeScript funciona nativamente; somente os wrappers opcionais
`skills/github/bin/github.sh` e `skills/push/bin/push.sh` requerem o Git Bash.
Nenhum componente requer WSL.

O pacote inclui as correções de portabilidade encontradas na validação real:
IDs de drafts do Docs usam nomes válidos no Windows, caminhos persistidos pelo
EvalFly são canônicos e independentes do sistema operacional, e verificações
de permissão POSIX continuam obrigatórias nas plataformas que as suportam.
Para repetir as suítes e o typecheck da extensão:

```powershell
./scripts/Test-OmpPantheon.ps1
```

Alguns pontos de entrada disponiveis depois da instalacao:

```text
/omomomo
/start-work
/ulw
/evalfly-enforce status
```

## Conhecimento da codebase

Dois MCPs locais ficam ativos em toda sessão do OMP:

- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)
  `0.9.0`, com indexação e watcher automáticos;
- [Graphify](https://github.com/Graphify-Labs/graphify) `0.9.31`, com o extra
  MCP e a skill oficial para Pi/OMP.

Instale ou restaure os runtimes em qualquer clone:

```powershell
./scripts/Install-OmpKnowledgeTools.ps1
```

A configuração stdio está em `agent/mcp.json`. Use `/graphify <caminho>` para
criar ou atualizar `graphify-out/graph.json`; o servidor Graphify também aceita
`project_path` para consultar outros projetos. Nenhum dos dois envia a codebase
para um serviço hospedado.

## Estado privado

O OMP também grava autenticação, sessões, bancos, caches e plugins instalados
na mesma árvore. Esses caminhos estão bloqueados pelo `.gitignore`:

- `agent/agent.db*`, sessões, blobs, memórias e caches;
- `.env`, `agent/secrets.yml` e `secret-placeholder.key`;
- tokens do auth broker/gateway;
- `plugins/node_modules`, caches e lock de estado dos plugins;
- identidade local `agent/kimi-device-id` e estado auxiliar `puppeteer/`;
- logs, relatórios, worktrees e bancos auxiliares.

Assim, a configuração autoral é versionada diretamente, enquanto credenciais
e estado de execução nunca aparecem em `git status`.

Antes de commitar:

```powershell
./scripts/Test-OmpConfigRepo.ps1
./scripts/Test-OmpConfigRepo.ps1 -Installed
./scripts/Test-OmpPantheon.ps1
git diff --cached
```

Referências oficiais:

- [Settings](https://github.com/can1357/oh-my-pi/blob/main/docs/settings.md)
- [Variáveis e diretórios](https://github.com/can1357/oh-my-pi/blob/main/docs/environment-variables.md)
- [Skills](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md)
- [Agentes](https://github.com/can1357/oh-my-pi/blob/main/docs/task-agent-discovery.md)
- [Plugins](https://github.com/can1357/oh-my-pi/blob/main/docs/plugin-manager-installer-plumbing.md)
- [MCP](https://github.com/can1357/oh-my-pi/blob/main/docs/mcp-config.md)
