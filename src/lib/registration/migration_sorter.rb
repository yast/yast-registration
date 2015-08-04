
module Registration
  # sort the migration products
  # first the extensions, then the base product, modules at the end
  # TODO: merge with ADDON_SORTER when SCC provides "free" and "product_type"
  # attributes
  MIGRATION_SORTER = proc do |x, y|
    if x.base != y.base
      # base at the end
      x.base ? 1 : -1
    else
      # sort the groups by name
      x.name <=> y.name
    end
  end
end
