#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/accounts.json"
ranked="$tmp_dir/ranked.json"
selected="$tmp_dir/selected.json"
pool="$tmp_dir/pool.json"

cat >"$fixture" <<'JSON'
[
  {
    "account_key": "paid-high",
    "email": "paid@example.invalid",
    "effective_plan": "plus",
    "source": "api",
    "fiveh_remaining": 90,
    "weekly_remaining": 90,
    "weekly_limit_present": true,
    "last_usage_at": 300
  },
  {
    "account_key": "free-low",
    "email": "free-low@example.invalid",
    "effective_plan": "free",
    "source": "api",
    "fiveh_remaining": 3,
    "weekly_remaining": -1,
    "weekly_limit_present": false,
    "last_usage_at": 200
  },
  {
    "account_key": "free-high",
    "email": "free-high@example.invalid",
    "effective_plan": "free",
    "source": "api",
    "fiveh_remaining": 42,
    "weekly_remaining": -1,
    "weekly_limit_present": false,
    "last_usage_at": 100
  },
  {
    "account_key": "stale-free",
    "email": "stale-free@example.invalid",
    "effective_plan": "free",
    "source": "cache",
    "fiveh_remaining": 99,
    "weekly_remaining": -1,
    "weekly_limit_present": false,
    "last_usage_at": 999
  },
  {
    "account_key": "team-excluded",
    "email": "team@example.invalid",
    "effective_plan": "team",
    "source": "api",
    "fiveh_remaining": 100,
    "weekly_remaining": 100,
    "weekly_limit_present": true,
    "last_usage_at": 400
  }
]
JSON

jq \
  --argjson min5 10 \
  --argjson minw 5 \
  --arg usable "free,plus,team" \
  '
    def usable_plans:
      (
        $usable
        | ascii_downcase
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
      );

    def plan_name:
      ((.effective_plan // .plan // "unknown") | ascii_downcase);

    def plan_usable:
      plan_name as $plan
      | (usable_plans | index($plan)) != null;

    def weekly_limit_present:
      (
        if has("weekly_limit_present") then
          .weekly_limit_present
        elif (.usage.secondary | type) == "object" and (.usage.secondary | has("present")) then
          .usage.secondary.present
        else
          false
        end
      ) == true;

    def weekly_available:
      (weekly_limit_present | not) or ((.weekly_remaining // -1) >= $minw);

    map(
      . + {
        available: (
          ((.source // "cache") == "api") and
          plan_usable and
          (.fiveh_remaining >= $min5) and
          weekly_available
        ),
        plan_bucket: (
          if ((.effective_plan // .plan // "") | ascii_downcase) == "free" then 0
          else 1
          end
        ),
        combined_priority: (-((.weekly_remaining // -1) + (.fiveh_remaining // -1))),
        weekly_priority: (-(.weekly_remaining // -1)),
        fiveh_priority: (-(.fiveh_remaining // -1)),
        freshness_priority: (-(.last_usage_at // 0))
      }
    )
    | sort_by([
      (.available | not),
      .plan_bucket,
      .combined_priority,
      .weekly_priority,
      .fiveh_priority,
      .freshness_priority
    ])
  ' "$fixture" >"$ranked"

jq --arg excludes "team" '
  (
    $excludes
    | ascii_downcase
    | split(",")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))
  ) as $ex
  | map(select(.available))
  | map(select(
      (((.effective_plan // .plan // "") | ascii_downcase)) as $p
      | ($ex | index($p)) == null
    ))
  | .[0]
' "$ranked" >"$selected"

jq \
  --arg excludes "team" \
  '
    def excluded_plans:
      (
        $excludes
        | ascii_downcase
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
      );

    def plan_name:
      ((.effective_plan // .plan // "unknown") | ascii_downcase);

    def plan_excluded:
      plan_name as $plan
      | (excluded_plans | index($plan)) != null;

    map(select(plan_excluded | not)) as $eligible
    | {
      total_accounts: ($eligible | length),
      available_count: ($eligible | map(select(.available)) | length),
      stale_count: ($eligible | map(select((.source // "cache") != "api")) | length),
      excluded_count: (length - ($eligible | length))
    }
  ' "$ranked" >"$pool"

selected_key="$(jq -r '.account_key // ""' "$selected")"
available_count="$(jq -r '.available_count' "$pool")"
stale_count="$(jq -r '.stale_count' "$pool")"
excluded_count="$(jq -r '.excluded_count' "$pool")"

[[ "$selected_key" == "free-high" ]] || {
  printf 'expected selected account free-high, got %s\n' "${selected_key:-<empty>}" >&2
  exit 1
}

[[ "$available_count" == "2" ]] || {
  printf 'expected available_count=2 after team exclusion, got %s\n' "$available_count" >&2
  exit 1
}

[[ "$stale_count" == "1" ]] || {
  printf 'expected stale_count=1, got %s\n' "$stale_count" >&2
  exit 1
}

[[ "$excluded_count" == "1" ]] || {
  printf 'expected excluded_count=1, got %s\n' "$excluded_count" >&2
  exit 1
}

printf 'selection fixtures passed\n'
