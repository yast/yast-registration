Yast Registration Module
========================

[![Build Status](https://travis-ci.org/yast/yast-registration.png?branch=master)](https://travis-ci.org/yast/yast-registration)
[![Coverage Status](https://coveralls.io/repos/yast/yast-registration/badge.png)](https://coveralls.io/r/yast/yast-registration)
[![Code Climate](https://codeclimate.com/github/yast/yast-registration.png)](https://codeclimate.com/github/yast/yast-registration)
[![License GPL-2.0](http://b.repl.ca/v1/license-GPL--2.0-blue.png)](http://www.gnu.org/licenses/gpl-2.0-standalone.html)
![Development Status](http://b.repl.ca/v1/status-development-yellow.png)

This is a YaST module for registering the system against [SUSE Customer Center](https://scc.suse.com)


Example Snippet for Autoyast registration
-----------------------------------------
```xml
  <suse_register>
      <do_registration config:type="boolean">true</do_registration>
      <reg_server>https://mysmt</reg_server>
      <reg_server_cert>text of our own certificate</reg_server_cert>
      <email>jreidinger@suse.com</email>
      <regcode>my secret SLES regcode</regcode>
      <install_updates config:type="boolean">true</install_updates>
      <slp_discovery config:type="boolean">false</slp_discovery>
      <addons>
        <addon>
          <name>addon name</name>
          <regcode>addon regcode</regcode>
        </addon>
      </addons>
  </suse_register>
```
