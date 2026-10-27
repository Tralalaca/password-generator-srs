param(
    [switch]$Preview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$plan = Get-Content (Join-Path $repoRoot 'docs/backlog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$repository = [string]$plan.repository
$owner = $repository.Split('/')[0]
$repoName = $repository.Split('/')[1]

function Invoke-GhCommand {
    param([string[]]$Arguments)
    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return ($output -join [Environment]::NewLine)
}

function Invoke-GhJson {
    param([string]$Endpoint, [string]$Method = 'GET', [object]$Payload = $null)
    $command = @('api', $Endpoint, '--method', $Method)
    $tempFile = $null
    try {
        if ($null -ne $Payload) {
            $tempFile = [IO.Path]::GetTempFileName()
            $json = ConvertTo-Json -InputObject $Payload -Depth 30 -Compress
            [IO.File]::WriteAllText($tempFile, $json, (New-Object Text.UTF8Encoding($false)))
            $command += @('--input', $tempFile)
        }
        $output = Invoke-GhCommand $command
        if ([string]::IsNullOrWhiteSpace($output)) { return $null }
        return ($output | ConvertFrom-Json)
    } finally {
        if ($tempFile -and (Test-Path -LiteralPath $tempFile)) { Remove-Item -LiteralPath $tempFile }
    }
}

function Assert-Plan {
    if ($plan.tasks.Count -lt 20 -or $plan.tasks.Count -gt 25) { throw 'Backlog must contain 20–25 tasks.' }
    if ($plan.milestones.Count -lt 3 -or $plan.milestones.Count -gt 4) { throw 'Plan must contain 3–4 milestones.' }
    $seen = @{}
    $milestones = @{}
    $dailyHours = @{}
    foreach ($milestone in $plan.milestones) { $milestones[$milestone.id] = $milestone }
    foreach ($task in $plan.tasks) {
        if ($seen.ContainsKey($task.id)) { throw "Duplicate task id $($task.id)." }
        if (-not $milestones.ContainsKey($task.milestone)) { throw "Unknown milestone for $($task.id)." }
        if ([datetime]$task.start -gt [datetime]$task.end) { throw "Invalid dates for $($task.id)." }
        if ([datetime]$task.end -gt [datetime]$milestones[$task.milestone].due) { throw "Task $($task.id) ends after its milestone." }
        foreach ($dependency in $task.dependsOn) {
            if (-not $seen.ContainsKey($dependency)) { throw "Dependency $dependency must precede $($task.id)." }
            if ([datetime]$seen[$dependency].end -ge [datetime]$task.start) { throw "Dependency $dependency must finish before $($task.id) starts." }
        }
        if ($task.criteria.Count -lt 2) { throw "Task $($task.id) needs more acceptance criteria." }
        $workdays = @()
        for ($date = [datetime]$task.start; $date -le [datetime]$task.end; $date = $date.AddDays(1)) {
            if ($date.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) { $workdays += $date.ToString('yyyy-MM-dd') }
        }
        if (-not $workdays.Count) { throw "Task $($task.id) has no working day." }
        foreach ($workday in $workdays) {
            if (-not $dailyHours.ContainsKey($workday)) { $dailyHours[$workday] = 0 }
            $dailyHours[$workday] += $task.hours / $workdays.Count
        }
        $seen[$task.id] = $task
    }
    foreach ($workday in $dailyHours.Keys) {
        if ($dailyHours[$workday] -gt 8.001) { throw "Single-person workload exceeds 8 hours on $workday." }
    }
}

function Get-IssueBody {
    param($Task, [hashtable]$IssueNumbers)
    $checks = ($Task.criteria | ForEach-Object { "- [ ] $_" }) -join "`n"
    $dependencies = if ($Task.dependsOn.Count) {
        ($Task.dependsOn | ForEach-Object { if ($IssueNumbers.ContainsKey($_)) { "#$($IssueNumbers[$_])" } else { $_ } }) -join ', '
    } else { 'нет' }
    $stage = @($plan.milestones | Where-Object { $_.id -eq $Task.milestone })[0]
    $specUrl = "https://github.com/$repository/blob/main/docs/technical-specification.md"
    return @"
<!-- plan-id: $($Task.id) -->
### User Story

$($Task.story)

### Acceptance Criteria

$checks

**Основная роль:** $($Task.role). **Сложность:** $($Task.complexity). **Оценка:** $($Task.hours) ч.

**План:** $($Task.start) — $($Task.end). **Контрольная точка:** $($stage.title) ($($stage.due)).

**Зависимости:** $dependencies.

**ТЗ:** [раздел $($Task.spec)]($specUrl).
"@
}

function Get-WikiText {
    param([hashtable]$IssueNumbers, [string]$RoadmapUrl)
    $milestoneRows = ($plan.milestones | ForEach-Object { "| $($_.title) | $($_.due) | $($_.description) |" }) -join "`n"
    $ganttRows = foreach ($milestone in $plan.milestones) {
        "section $($milestone.title)"
        foreach ($task in @($plan.tasks | Where-Object milestone -eq $milestone.id)) {
            $endExclusive = ([datetime]$task.end).AddDays(1).ToString('yyyy-MM-dd')
            "$($task.id) : $($task.id.Replace('-', '').ToLowerInvariant()), $($task.start), $endExclusive"
        }
    }
    $gantt = $ganttRows -join "`n"
    $taskRows = ($plan.tasks | ForEach-Object {
        $number = $IssueNumbers[$_.id]
        $label = if ($number) { "[#$number](https://github.com/$repository/issues/$number)" } else { $_.id }
        $depends = if ($_.dependsOn.Count) { ($_.dependsOn | ForEach-Object { if ($IssueNumbers[$_]) { "#$($IssueNumbers[$_])" } else { $_ } }) -join ', ' } else { '—' }
        "| $label | $($_.title) | $($_.start) | $($_.end) | $($_.role) | $depends |"
    }) -join "`n"
    $roadmap = if ($RoadmapUrl) { "[Открыть Roadmap]($RoadmapUrl)" } else { 'Ссылка появится после публикации GitHub Project.' }
    $roleNote = if ($IssueNumbers.Count) { 'основная роль каждой задачи указана в её метке.' } else { 'основная роль каждой задачи предусмотрена в её метке при публикации.' }
    $projectNote = if ($RoadmapUrl) { 'Даты начала и окончания каждого Issue также заданы в полях Project. Зависимости перечислены в Issues и оформлены связями «Blocked by».' } else { 'При публикации даты будут перенесены в поля Project, а зависимости — в описания Issues и связи «Blocked by».' }
    return @"
<!-- generated-from: docs/backlog.json -->
# План проекта «Генератор сложных паролей»

План составлен по [техническому заданию](https://github.com/$repository/blob/main/docs/technical-specification.md). Приложение работает в браузере: серверная логика и база данных для паролей не нужны. Один исполнитель выполняет несколько ролей; $roleNote

## 1. Участник и роли

| Роль | Исполнитель | Обязанности |
| --- | --- | --- |
| Менеджер проекта | @$owner | Сроки, зависимости, контроль этапов |
| Дизайнер | @$owner | Макеты и состояния интерфейса |
| Frontend-разработчик | @$owner | Браузерное приложение и настройка генерации |
| QA-инженер | @$owner | Проверки требований, безопасности и выпуска |

Backend-разработка не запланирована, поскольку по ТЗ пароль создаётся только в браузере и не передаётся на сервер.

## 2. Беклог и контрольные точки

**Всего задач:** $($plan.tasks.Count). **Оценка:** $(($plan.tasks | Measure-Object -Property hours -Sum).Sum) ч. **Период:** 28.10.2026–11.12.2026. Сложность: большая — $( @($plan.tasks | Where-Object complexity -eq 'large').Count ), средняя — $( @($plan.tasks | Where-Object complexity -eq 'medium').Count ), малая — $( @($plan.tasks | Where-Object complexity -eq 'small').Count ).

В Project входят только 24 детализированные задачи PG-01–PG-24. Существующие Issues #8–#14 сохраняются как требования верхнего уровня; старые Issues #2–#7 относятся к прежней теме репозитория и в этот план не входят.

| Контрольная точка | Срок | Результат |
| --- | --- | --- |
$milestoneRows

| Issue | Задача | Начало | Окончание | Основная роль | Зависит от |
| --- | --- | --- | --- | --- | --- |
$taskRows

## 3. Диаграмма Ганта

$roadmap

``````mermaid
gantt
    title Разработка генератора сложных паролей
    dateFormat YYYY-MM-DD
    axisFormat %d.%m
$gantt
``````

$projectNote

## 4. Проверка результата

Выпуск завершён, когда реализованы критерии ТЗ, пройдены автоматические проверки, подтверждены отсутствие сохранения и передачи пароля, а браузерная приёмка и ограничения зафиксированы в README.
"@
}

Assert-Plan
if ($Preview) {
    $previewMap = @{}
    $issueMapFile = Join-Path $repoRoot 'docs/issue-map.json'
    if (Test-Path -LiteralPath $issueMapFile) {
        $savedMap = Get-Content -LiteralPath $issueMapFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $savedMap.PSObject.Properties) { $previewMap[$property.Name] = [int]$property.Value }
    }
    $previewFile = Join-Path $repoRoot 'docs/wiki-project-plan.md'
    [IO.File]::WriteAllText($previewFile, (Get-WikiText $previewMap ''), (New-Object Text.UTF8Encoding($false)))
    $issuePreview = Join-Path $repoRoot 'docs/issues-preview.md'
    $issueText = ($plan.tasks | ForEach-Object { "# $($_.id) — $($_.title)`n`n$(Get-IssueBody $_ $previewMap)" }) -join "`n`n---`n`n"
    [IO.File]::WriteAllText($issuePreview, $issueText, (New-Object Text.UTF8Encoding($false)))
    Write-Output "Validated $($plan.tasks.Count) tasks and wrote Wiki and Issue previews. No GitHub changes were made."
    exit 0
}

Invoke-GhCommand @('auth', 'status') | Out-Null
Invoke-GhCommand @('project', 'list', '--owner', $owner, '--limit', '1', '--format', 'json') | Out-Null
$roleLabels = @(
    @{ name = 'role: project-manager'; color = '5319e7'; description = 'Планирование и координация' },
    @{ name = 'role: designer'; color = 'd876e3'; description = 'Дизайн интерфейса' },
    @{ name = 'role: frontend'; color = '1d76db'; description = 'Браузерное приложение' },
    @{ name = 'role: qa'; color = '0e8a16'; description = 'Проверка качества' },
    @{ name = 'complexity: small'; color = 'c2e0c6'; description = 'Малая сложность' },
    @{ name = 'complexity: medium'; color = 'fbca04'; description = 'Средняя сложность' },
    @{ name = 'complexity: large'; color = 'd93f0b'; description = 'Высокая сложность' }
)
$existingLabels = @(Invoke-GhJson "repos/$repository/labels?per_page=100")
foreach ($label in $roleLabels) {
    if (-not @($existingLabels | Where-Object name -eq $label.name).Count) {
        Invoke-GhJson "repos/$repository/labels" 'POST' $label | Out-Null
    }
}

$milestoneNumbers = @{}
$existingMilestones = @(Invoke-GhJson "repos/$repository/milestones?state=all&per_page=100")
foreach ($milestone in $plan.milestones) {
    $found = @($existingMilestones | Where-Object title -eq $milestone.title)
    $payload = @{
        title = $milestone.title; description = $milestone.description
        due_on = "$($milestone.due)T20:59:59Z"
    }
    if ($found.Count) {
        $number = [int]$found[0].number
        Invoke-GhJson "repos/$repository/milestones/$number" 'PATCH' $payload | Out-Null
    } else {
        $created = Invoke-GhJson "repos/$repository/milestones" 'POST' $payload
        $number = [int]$created.number
    }
    $milestoneNumbers[$milestone.id] = $number
}

$existingIssues = @(Invoke-GhJson "repos/$repository/issues?state=all&per_page=100") | Where-Object { -not $_.pull_request }
$issueNumbers = @{}
foreach ($task in $plan.tasks) {
    $body = Get-IssueBody $task $issueNumbers
    $existing = @($existingIssues | Where-Object { $_.body -match "<!-- plan-id: $($task.id) -->" })
    $payload = @{
        title = $task.title; body = $body; assignees = @($plan.assignee)
        labels = @("role: $($task.role)", "complexity: $($task.complexity)")
        milestone = $milestoneNumbers[$task.milestone]
    }
    if ($existing.Count) {
        $number = [int]$existing[0].number
        Invoke-GhJson "repos/$repository/issues/$number" 'PATCH' $payload | Out-Null
    } else {
        $created = Invoke-GhJson "repos/$repository/issues" 'POST' $payload
        $number = [int]$created.number
    }
    $issueNumbers[$task.id] = $number
    Write-Output "$($task.id) → #$number"
}

foreach ($task in $plan.tasks) {
    $number = $issueNumbers[$task.id]
    $existingDependencies = @(Invoke-GhJson "repos/$repository/issues/$number/dependencies/blocked_by?per_page=100")
    foreach ($dependency in $task.dependsOn) {
        $blockedByNumber = $issueNumbers[$dependency]
        if (-not @($existingDependencies | Where-Object number -eq $blockedByNumber).Count) {
            Invoke-GhCommand @('issue', 'edit', [string]$number, '--repo', $repository, '--add-blocked-by', [string]$blockedByNumber) | Out-Null
        }
    }
}

$projects = (Invoke-GhCommand @('project', 'list', '--owner', $owner, '--limit', '100', '--format', 'json') | ConvertFrom-Json).projects
$project = @($projects | Where-Object title -eq $plan.projectTitle)
if ($project.Count) { $project = $project[0] }
else { $project = Invoke-GhCommand @('project', 'create', '--owner', $owner, '--title', $plan.projectTitle, '--format', 'json') | ConvertFrom-Json }
$projectNumber = [int]$project.number
Invoke-GhCommand @('project', 'link', [string]$projectNumber, '--owner', $owner, '--repo', $repoName) | Out-Null
$fieldList = (Invoke-GhCommand @('project', 'field-list', [string]$projectNumber, '--owner', $owner, '--format', 'json') | ConvertFrom-Json).fields
foreach ($fieldName in @('Start date', 'Target date')) {
    if (-not @($fieldList | Where-Object name -eq $fieldName).Count) {
        Invoke-GhCommand @('project', 'field-create', [string]$projectNumber, '--owner', $owner, '--name', $fieldName, '--data-type', 'DATE') | Out-Null
    }
}
$items = (Invoke-GhCommand @('project', 'item-list', [string]$projectNumber, '--owner', $owner, '--limit', '100', '--format', 'json') | ConvertFrom-Json).items
foreach ($task in $plan.tasks) {
    $url = "https://github.com/$repository/issues/$($issueNumbers[$task.id])"
    if (-not @($items | Where-Object { $_.content.url -eq $url }).Count) {
        Invoke-GhCommand @('project', 'item-add', [string]$projectNumber, '--owner', $owner, '--url', $url) | Out-Null
    }
    Invoke-GhCommand @('project', 'item-edit', [string]$projectNumber, '--owner', $owner, '--url', $url, '--field', 'Start date', '--date', $task.start) | Out-Null
    Invoke-GhCommand @('project', 'item-edit', [string]$projectNumber, '--owner', $owner, '--url', $url, '--field', 'Target date', '--date', $task.end) | Out-Null
}

$query = 'query($login:String!,$number:Int!){user(login:$login){projectV2(number:$number){id views(first:100){nodes{name number layout}}}}}'
$projectData = Invoke-GhJson 'graphql' 'POST' @{ query = $query; variables = @{ login = $owner; number = $projectNumber } }
$projectNode = $projectData.data.user.projectV2
if (-not $projectNode) { throw 'Project node was not found through GraphQL.' }
$roadmapView = @($projectNode.views.nodes | Where-Object { $_.name -eq 'Roadmap' -and $_.layout -eq 'ROADMAP' })
if ($roadmapView.Count) { $viewNumber = [int]$roadmapView[0].number }
else {
    $mutation = 'mutation($input:CreateProjectV2ViewInput!){createProjectV2View(input:$input){projectV2View{name number layout}}}'
    $viewData = Invoke-GhJson 'graphql' 'POST' @{ query = $mutation; variables = @{ input = @{ projectId = $projectNode.id; name = 'Roadmap'; layout = 'ROADMAP' } } }
    if ($viewData.errors) { throw ($viewData.errors | ConvertTo-Json -Depth 10) }
    $viewNumber = [int]$viewData.data.createProjectV2View.projectV2View.number
}
$projectUrl = if ($project.url) { [string]$project.url } else { "https://github.com/users/$owner/projects/$projectNumber" }
$roadmapUrl = "$projectUrl/views/$viewNumber"

$wikiText = Get-WikiText $issueNumbers $roadmapUrl
[IO.File]::WriteAllText((Join-Path $repoRoot 'docs/wiki-project-plan.md'), $wikiText, (New-Object Text.UTF8Encoding($false)))
Invoke-GhCommand @('auth', 'setup-git') | Out-Null
$wikiDir = Join-Path ([IO.Path]::GetTempPath()) ("password-generator-wiki-" + [guid]::NewGuid().ToString('N'))
try {
    $cloneOutput = & git clone "https://github.com/$repository.wiki.git" $wikiDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Cannot clone GitHub Wiki: $($cloneOutput -join [Environment]::NewLine)" }
    $page = Join-Path $wikiDir 'План-проекта.md'
    if ((Test-Path -LiteralPath $page) -and ((Get-Content -LiteralPath $page -Raw -Encoding UTF8) -notmatch '<!-- generated-from: docs/backlog.json -->')) {
        throw 'Wiki page exists but was not generated by this plan; review it before replacing.'
    }
    [IO.File]::WriteAllText($page, $wikiText, (New-Object Text.UTF8Encoding($false)))
    & git -C $wikiDir add -- 'План-проекта.md'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage Wiki page.' }
    & git -C $wikiDir diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        & git -C $wikiDir commit -m 'Add project plan for password generator'
        if ($LASTEXITCODE -ne 0) { throw 'Cannot commit Wiki page.' }
        & git -C $wikiDir push
        if ($LASTEXITCODE -ne 0) { throw 'Cannot push Wiki page.' }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($wikiDir)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'password-generator-wiki-*') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
Write-Output "Published $($plan.tasks.Count) issues, four milestones, Project Roadmap, and Wiki page: $roadmapUrl"

