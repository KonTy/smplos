function _smplos_tide_setup
    set -U VIRTUAL_ENV_DISABLE_PROMPT true
    source (functions --details _tide_sub_configure)
    _load_config rainbow
    _tide_finish
end

function _tide_init_install --on-event _tide_init_install
    _smplos_tide_setup
end

function _tide_init_update --on-event _tide_init_update
    set -q tide_jobs_number_threshold || set -U tide_jobs_number_threshold 1000
end

function _tide_init_uninstall --on-event _tide_init_uninstall
    set -e VIRTUAL_ENV_DISABLE_PROMPT
    set -e (set -U --names | string match --entire -r '^_?tide')
    functions --erase (functions --all | string match --entire -r '^_?tide')
end

# smplOS: Auto-configure tide rainbow on first launch
# (fisher events don't fire when tide is shipped directly)
if not set -q tide_left_prompt_items
    _smplos_tide_setup
end
