
module Registration

  # Sorter for sorting Addons in required display order
  # (first paid extensions, then free extensions, modules at the end
  # see https://bugzilla.novell.com/show_bug.cgi?id=888567#c21)
  ADDON_SORTER = Proc.new do |x, y|
    if x.product_type != y.product_type
      # simplification: "extension" is lexicographically before "module"
      # as requested in the display order so take advantage of this...
      x.product_type.to_s <=> y.product_type.to_s
    elsif x.free != y.free
      # paid (non-free) first
      x.free ? 1 : -1
    else
      # sort the groups by name
      x.name <=> y.name
    end
  end

end
