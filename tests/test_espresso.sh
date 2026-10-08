#!/bin/bash
# espresso CLI 的轻量测试:时长解析 / 格式化 / 供电解析与提醒(pmset、sudo、launchctl 都用替身,不碰真实系统)
# 运行: ./tests/test_espresso.sh
set -uo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=../espresso
source ./espresso
set +e

PASS=0 FAIL=0
check() {   # check <描述> <期望> <实际>
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); printf 'FAIL: %s — expected [%s], got [%s]\n' "$1" "$2" "$3"; fi
}

# 合法时长 -> 分钟
for case in 1m:1 90m:90 1h:60 2h:120 8h:480 1h30m:90 08h:480 0h5m:5 168h:10080 10080m:10080; do
    check "parse ${case%%:*}" "${case##*:}" "$(parse_duration "${case%%:*}")"
done

# 非法时长 -> 返回 1 且无输出
for bad in "" 0 0m 0h 0h0m -1h -30m 90 1.5h 1d 1s h m 1hm 1m1h " 1h" "1h " 1H abc 169h 10081m 999999h; do
    out="$(parse_duration "$bad")"; rc=$?
    check "reject '$bad' (rc)" 1 "$rc"
    check "reject '$bad' (no output)" "" "$out"
done

for case in 1:1m 45:45m 60:1h 90:1h\ 30m 720:12h; do
    check "fmt ${case%%:*}" "${case#*:}" "$(fmt_minutes "${case%%:*}")"
done

# batt <来源> <电池状态> -> 模拟 `pmset -g batt` 的输出
batt() { printf "Now drawing from '%s'\n -InternalBattery-0 (id=1)\t%s present: true\n" "$1" "$2"; }
check "power AC" AC "$(batt 'AC Power' '100%; charged; 0:00 remaining' | parse_power_source)"
check "power AC not charging" AC "$(batt 'AC Power' '80%; AC attached; not charging' | parse_power_source)"
check "power battery" Battery "$(batt 'Battery Power' '80%; discharging; 3:10 remaining' | parse_power_source)"
check "power low battery" Battery "$( { batt 'Battery Power' '9%; discharging; 0:18 remaining'; printf '\tBattery Warning: Early\n'; } | parse_power_source)"
check "power polling stopped" Battery "$( { echo '* Battery Polling is Stopped'; batt 'Battery Power' '80%; discharging; (no estimate)'; } | parse_power_source)"
check "power sandbox fallback" Battery "$(batt 'AC Power' '80%; discharging; 3:10 remaining' | parse_power_source)"
check "power UPS" UPS "$(printf "Now drawing from 'UPS Power'\n -UPS1500 (id=2)\t95%%; discharging; 0:40 remaining present: true\n" | parse_power_source)"
check "power desktop" AC "$(printf "Now drawing from 'AC Power'" | parse_power_source)"
check "power unknown" Unknown "$(printf '' | parse_power_source)"

for case in AC:AC:电源适配器 Battery:Battery:电池 UPS:UPS:UPS Unknown:Unknown:未知; do
    IFS=: read -r src en zh <<< "$case"
    check "label en $src" "$en" "$(PREF=en power_label "$src")"
    check "label zh $src" "$zh" "$(PREF=zh power_label "$src")"
done

# 跨天的时间带星期
check "clock today" "$(date +%H:%M)" "$(fmt_clock "$(date +%s)")"
check "clock other day" "$(date -r $(( $(date +%s) + 172800 )) '+%a %H:%M')" "$(fmt_clock $(( $(date +%s) + 172800 )))"

# status / on / for 按真实脚本的 set -e 跑完整流程,系统命令全换成替身
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/pmset" <<'EOF'
#!/bin/bash
# 替身 pmset:状态存在同目录的文件里;有 batt2 时停顿后再写一次,模拟低电量时 pmset 分两次写
dir="$(dirname "$0")"
case "$*" in
    -g)                  printf ' SleepDisabled\t\t%s\n' "$(cat "$dir/disabled")" ;;
    "-g batt")           [ ! -f "$dir/batt-fail" ] || exit 1
                         cat "$dir/batt"
                         if [ -f "$dir/batt2" ]; then sleep 0.2; cat "$dir/batt2"; fi ;;
    "-a disablesleep "*) printf '%s\n' "$3" > "$dir/disabled" ;;
esac
EOF
chmod +x "$STUB/pmset"
: > "$STUB/sudoers"

# stub <SleepDisabled> <pmset -g batt 的输出> [第二次写的内容 | fail]
stub() {
    rm -f "$STUB/batt2" "$STUB/batt-fail" "$STUB/deadline"
    printf '%s\n' "$1" > "$STUB/disabled"
    printf '%s' "$2" > "$STUB/batt"
    case "${3:-}" in
        fail) : > "$STUB/batt-fail" ;;
        ?*)   printf '%s' "$3" > "$STUB/batt2" ;;
    esac
}
# run <语言> <命令...> -> stdout 加一行 rc=<退出码>;stderr 写到 $STUB/err
run() {
    local lang="$1"; shift
    ( PMSET="$STUB/pmset" SUDOERS="$STUB/sudoers" PREF="$lang"
      DEADLINE_FILE="$STUB/deadline" AGENT_PLIST="$STUB/agent.plist"
      sudo() { shift; "$@"; }
      launchctl() { :; }
      ensure_agent() { :; }
      set -e; "$@" ) 2>"$STUB/err"
    echo "rc=$?"
}

ON_EN=$'on  (SleepDisabled=1, no-sleep active)\ntimer: none (until turned off)'
WARN_BATT='WARNING: no-sleep is active on battery power — the Mac will keep running and may drain the battery.'
WARN_UPS='WARNING: no-sleep is active on UPS power — the Mac will keep running and may drain the UPS.'
BATT="$(batt 'Battery Power' '80%; discharging; 3:10 remaining')"
LOW="$(batt 'Battery Power' '9%; discharging; 0:18 remaining')"
AC="$(batt 'AC Power' '100%; charged; 0:00 remaining')"
UPS="$(printf "Now drawing from 'UPS Power'\n -UPS1500 (id=2)\t95%%; discharging; 0:40 remaining present: true")"

stub 1 "$LOW"$'\n' $'\tBattery Warning: Early\n'
check "status low battery (pmset writes twice)" "$ON_EN"$'\npower: Battery\n'"$WARN_BATT"$'\nrc=0' "$(run en do_status)"
stub 1 "" fail
check "status pmset batt fails" "$ON_EN"$'\npower: Unknown\nrc=0' "$(run en do_status)"
stub 0 "$BATT"
check "status off on battery" $'off (SleepDisabled=0, normal sleep)\npower: Battery\nrc=1' "$(run en do_status)"
stub 1 "$BATT"
check "status zh" $'on  (SleepDisabled=1,防休眠中)\n定时:无(直到手动关闭)\n供电:电池\n警告:正在用电池供电且防休眠开启 —— Mac 会持续运行,可能耗尽电量\nrc=0' "$(run zh do_status)"
stub 1 "$UPS"
check "status UPS" "$ON_EN"$'\npower: UPS\n'"$WARN_UPS"$'\nrc=0' "$(run en do_status)"
stub 1 "$AC"
check "status AC" "$ON_EN"$'\npower: AC\nrc=0' "$(run en do_status)"

stub 0 "$BATT"
check "on battery (stdout)" $'No-sleep ON (SleepDisabled=1) — stays awake even lid-closed\nrc=0' "$(run en do_on)"
check "on battery (stderr)" "$WARN_BATT" "$(cat "$STUB/err")"
check "on battery (pmset)" 1 "$(cat "$STUB/disabled")"
stub 0 "$AC"
check "on AC (rc)" rc=0 "$(run en do_on | tail -1)"
check "on AC (no warning)" "" "$(cat "$STUB/err")"
stub 0 "$BATT"
check "for battery (rc)" rc=0 "$(run en do_for 1h | tail -1)"
check "for battery (stderr)" "$WARN_BATT" "$(cat "$STUB/err")"

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
