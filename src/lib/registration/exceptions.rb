# ------------------------------------------------------------------------------
# Copyright (c) 2014 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------
#
#
module Registration
  # Exception class for handling all Pkg errors
  class PkgError < RuntimeError
  end

  # Exception class for handling service errors
  class ServiceError < PkgError
    attr_reader :service

    def initialize(msg, service)
      super(msg)
      @service = service
    end
  end

  class SourceRestoreError < PkgError
  end

  # generic download error
  class DownloadError < RuntimeError
  end

  # User decision to abort because libzypp has already been
  # locked by another application.
  class PkgAborted < RuntimeError
  end
end
