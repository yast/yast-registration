# encoding: utf-8

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

require "yast"

module Registration
  Yast.import "Pkg"
  Yast.import "Installation"
  Yast.import "PackageCallbacksInit"

  class SwMgmt
    include Yast

    def self.init
      # display progress when refreshing repositories
      PackageCallbacksInit.InitPackageCallbacks
      Pkg.TargetInitialize(Installation.destdir)
      Pkg.TargetLoad
      Pkg.SourceStartManager(true)
    end

    def self.save
      Pkg.SourceSaveAll
    end
  end
end

