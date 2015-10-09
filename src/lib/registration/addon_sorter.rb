
module Registration
  # Sorter for sorting Addons in required display order
  # (first paid extensions, then free extensions, modules at the end
  # see https://bugzilla.novell.com/show_bug.cgi?id=888567#c21)
  # @param x [Registration::Addon] the first item to compare
  # @param y [Registration::Addon] the second item to compare
  ADDON_SORTER = proc do |x, y|
    if x.product_type != y.product_type
      begin
        # if empty or nil move at the end
        if !x.product_type || x.product_type.empty?
          1
        elsif !y.product_type || y.product_type.empty?
          -1
        else
          # simplification: "extension" is lexicographically before "module"
          # as requested in the display order so take advantage of this...
          x.product_type <=> y.product_type
        end
      end
    elsif x.free != y.free
      # paid (non-free) first
      x.free ? 1 : -1
    else
      # sort the groups by label ("friendly_name" or "name" attribute)
      x.label <=> y.label
    end
  end
end
