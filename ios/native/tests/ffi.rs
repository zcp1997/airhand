//! Exercise public C ABI contracts without connecting to any external service.
use airhand_ios::*;
use std::ffi::{CStr, CString};
use std::ptr;

unsafe fn take(value: *mut std::ffi::c_char) -> String {
    assert!(!value.is_null());
    let text = unsafe { CStr::from_ptr(value) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { ah_string_free(value) };
    text
}

#[test]
fn protocol_version_matches_the_shared_core() {
    assert_eq!(ah_protocol_version(), airhand_proto::SIGNAL_VERSION as i32);
}

#[test]
fn fingerprints_accept_empty_and_exact_hex_but_reject_malformed_input() {
    for text in ["".to_owned(), "ab".repeat(32), ["AB"; 32].join(":")] {
        let value = CString::new(text).unwrap();
        assert!(unsafe { ah_check_fingerprint(value.as_ptr()) }.is_null());
    }
    assert!(unsafe { ah_check_fingerprint(ptr::null()) }.is_null());
    for text in ["xx".repeat(32), "ab".repeat(31), "fingerprint: ab".into()] {
        let value = CString::new(text).unwrap();
        let error = unsafe { take(ah_check_fingerprint(value.as_ptr())) };
        assert!(error.contains("fingerprint"));
    }
}

#[test]
fn invalid_configuration_and_utf8_return_owned_errors_without_starting() {
    for text in [b"{\0".as_slice(), b"{}\0".as_slice(), b"\xff\0".as_slice()] {
        let mut error = ptr::null_mut();
        assert_eq!(unsafe { ah_ctl_start(text.as_ptr().cast(), &mut error) }, 0);
        assert!(!unsafe { take(error) }.is_empty());
        let mut error = ptr::null_mut();
        assert_eq!(
            unsafe { ah_host_start(text.as_ptr().cast(), &mut error) },
            0
        );
        assert!(!unsafe { take(error) }.is_empty());
    }
    assert_eq!(unsafe { ah_ctl_start(ptr::null(), ptr::null_mut()) }, 0);
    assert_eq!(unsafe { ah_host_start(ptr::null(), ptr::null_mut()) }, 0);
}

#[test]
fn invalid_handles_are_safe_and_report_disconnected() {
    let handle = i64::MIN;
    ah_ctl_stop(handle);
    ah_host_stop(handle);
    assert!(ah_ctl_poll_event(handle, -1).is_null());
    assert!(ah_host_poll_event(handle, -1).is_null());
    let reply: serde_json::Value =
        serde_json::from_str(&unsafe { take(ah_ctl_call(handle, ptr::null())) }).unwrap();
    assert_eq!(reply["err"]["kind"], "notConnected");
    // A stopped host must release an encoder waiting for a send window.
    assert!(ah_host_wait_window(handle, 0));
    assert!(ah_host_tick(handle).is_null());
    unsafe {
        ah_string_free(ptr::null_mut());
        ah_bytes_free(ptr::null_mut(), 0);
    }
}
