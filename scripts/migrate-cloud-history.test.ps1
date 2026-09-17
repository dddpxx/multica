$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$migration = Join-Path $PSScriptRoot "migrate-cloud-history.ps1"
$before = docker exec multica-postgres-1 psql -U multica -d multica -At -c `
    "SELECT count(*) FROM agent_task_queue; SELECT count(*) FROM chat_session; SELECT count(*) FROM chat_message; SELECT count(*) FROM task_message;"

$plan = & $migration -PlanOnly | ConvertFrom-Json

$after = docker exec multica-postgres-1 psql -U multica -d multica -At -c `
    "SELECT count(*) FROM agent_task_queue; SELECT count(*) FROM chat_session; SELECT count(*) FROM chat_message; SELECT count(*) FROM task_message;"

Assert-True (($before -join ",") -eq ($after -join ",")) "PlanOnly changed the local database"
Assert-True ($plan.can_apply -eq $true) "migration plan is not safe to apply"
Assert-True ($plan.cloud.tasks -gt 0) "cloud task history was not discovered"
Assert-True ($plan.cloud.chat_sessions -gt 0) "cloud chat history was not discovered"
Assert-True ($plan.mapping.unmatched_issues -eq 0) "issue mapping is incomplete"
Assert-True ($plan.mapping.unmatched_projects -eq 0) "project mapping is incomplete"
Assert-True ($plan.mapping.unmatched_agents -eq 0) "agent mapping is incomplete"
Assert-True ($plan.cloud.non_terminal_tasks -eq 0) "active cloud tasks must not be imported"

"PASS: migration plan is complete and read-only"
