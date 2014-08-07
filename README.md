Yast Registration Module
========================

[![Build Status](https://travis-ci.org/yast/yast-registration.png?branch=master)](https://travis-ci.org/yast/yast-registration)
[![Coverage Status](https://coveralls.io/repos/yast/yast-registration/badge.png)](https://coveralls.io/r/yast/yast-registration)
[![Code Climate](https://codeclimate.com/github/yast/yast-registration.png)](https://codeclimate.com/github/yast/yast-registration)
[![Inline Docs](http://inch-ci.org/github/yast/yast-registration.png?branch=master)](http://inch-ci.org/github/yast/yast-registration)
[![License GPL-2.0](http://b.repl.ca/v1/license-GPL--2.0-blue.png)](http://www.gnu.org/licenses/gpl-2.0-standalone.html)
![Development Status](http://b.repl.ca/v1/status-development-yellow.png)

This is a YaST module for registering the system against [SUSE Customer Center](https://scc.suse.com)


Example Snippet for Autoyast Registration
-----------------------------------------
```xml
  <suse_register>
      <do_registration config:type="boolean">true</do_registration>
      <!-- if you use SMT specify the server URL here -->
      <reg_server>https://smt.example.com</reg_server>
      <!-- optionally download the SMT SSL certificate (not recommended, see below) -->
      <reg_server_cert>http://smt.example.com/smt.crt</reg_server_cert>
      <!-- optional server certificate fingerprint - the matching certificate
           will be automatically imported (more secure than "reg_server_cert") -->
      <reg_server_cert_fingerprint_type>SHA1</reg_server_cert_fingerprint_type>
      <reg_server_cert_fingerprint>01:23:...:CD:EF</reg_server_cert_fingerprint>

      <email>user@example.com</email>
      <regcode>my_secret_SLES_regcode</regcode>
      <install_updates config:type="boolean">true</install_updates>
      <slp_discovery config:type="boolean">false</slp_discovery>

      <--! optionally register an extension or module -->
      <addons config:type="list">
        <addon>
          <name>sle-sdk</name>
          <version>12</version>
          <arch>x86_64</arch>
          <release_type>nil</release_type>
          <--! a reg code is not needed for SDK -->
          <reg_code/>
        </addon>
      </addons>
  </suse_register>
```
