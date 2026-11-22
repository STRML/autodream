#!/bin/bash
worker_text_of() {
  awk '
    /^worker exit code: / { after_exit = 1; next }
    !after_exit {
      if (in_dump) next
      if (/^worker wrote output with no usable \.findings key/) { in_dump = 1; next }
      if (/^worker exceeded AUTODREAM_L1_TIMEOUT=/ || /^worker produced no findings JSON for /) next
      if (/^the sandbox for .* could not be built/ || /^could not make the staging directory / || /^no staging root is set, / || /^the answer path was a symlink/) next
      print
      next
    }
    /^--- worker stdout, last 40 lines ---$/ { in_stdout = 1; next }
    /^--- an omp log touched during this round/ || /^curl could not be run here/ || /^no route to / { exit }
    in_stdout { print }
  ' "$1"
}

classify_failure() {
  local errfile="$1" exit_code worker_text sep code

  if [ ! -s "$errfile" ]; then
    printf '%s\n' unclassified
    return 0
  fi

  exit_code=$(sed -n 's/^worker exit code: \([0-9][0-9]*\) after .*/\1/p' "$errfile" | tail -n 1)
  case "$exit_code" in
    ''|*[!0-9]*)
      printf '%s\n' unclassified
      return 0
      ;;
  esac

  if [ "$exit_code" -eq 0 ] && grep -qx 'worker stdout was empty' "$errfile"; then
    printf '%s\n' silent
    return 0
  fi

  worker_text=$(worker_text_of "$errfile")

  sep='[[:space:]_-]'

  if printf '%s\n' "$worker_text" \
      | grep -Eiq "not${sep}+logged${sep}+in|please${sep}+run${sep}+/login|oauth${sep}+token${sep}+(has${sep}+)?expired"; then
    printf '%s\n' provider
    return 0
  fi

  if printf '%s\n' "$worker_text" \
      | grep -Eiq "context${sep}*(length|limit|window|size)|too${sep}+(long|large)|tokens?${sep}+limit|max(imum)?${sep}+(input${sep}+)?(context|tokens?|length)|input${sep}+(length|tokens?)|exceed(s|ed)?${sep}+(the${sep}+)?(context|token)"; then
    printf '%s\n' size
    return 0
  fi

  code='(429|401|403|5[0-9][0-9]|5xx)([^0-9]|$)'
  if printf '%s\n' "$worker_text" \
      | grep -Eiq "(http(/[0-9.]+)?|status|code|error)([^0-9a-z]+(http|status|code|was|is|of|returned|with))*[^0-9a-z]{1,3}${code}|(^|[^0-9a-z])5xx([^0-9a-z]|$)|rate${sep}?limit|too${sep}+many${sep}+requests|overload|quota|unauthori[sz]ed|forbidden|service${sep}+unavailable|bad${sep}+gateway|gateway${sep}+time${sep}?out|internal${sep}+server${sep}+error|invalid${sep}+api${sep}+key|auth(entication|ori[sz]ation)?${sep}+(error|failed|failure)|token${sep}+expired"; then
    printf '%s\n' provider
    return 0
  fi

  printf '%s\n' size
}

provider_is_permanent() {
  local errfile="$1"
  [ -s "$errfile" ] || return 1
  worker_text_of "$errfile" \
    | grep -Ei 'error|http|status|code|429|402' \
    | grep -Eiq 'insufficient[[:space:]_-]*(balance|quota|funds)|no[[:space:]_-]+resource[[:space:]_-]+package|credit[[:space:]_-]+balance[[:space:]_-]+is[[:space:]_-]+too[[:space:]_-]+low|"code"[[:space:]]*:[[:space:]]*"?1113"?'
}
