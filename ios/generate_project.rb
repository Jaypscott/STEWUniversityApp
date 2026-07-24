require "xcodeproj"

root = File.expand_path(__dir__)
project_path = File.join(root, "STEWUniversity.xcodeproj")
project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2660"
project.root_object.attributes["LastUpgradeCheck"] = "2660"

app = project.new_target(:application, "STEWUniversity", :ios, "26.0")
tests = project.new_target(:unit_test_bundle, "STEWUniversityTests", :ios, "26.0")
ui_tests = project.new_target(:ui_test_bundle, "STEWUniversityUITests", :ios, "26.0")

main_group = project.main_group.new_group("STEWUniversity", "STEWUniversity")
Dir[File.join(root, "STEWUniversity", "*.swift")].sort.each do |path|
  ref = main_group.new_reference(File.basename(path))
  app.source_build_phase.add_file_reference(ref)
end

asset_catalog_path = File.join(root, "STEWUniversity", "Assets.xcassets")
if File.directory?(asset_catalog_path)
  asset_catalog_ref = main_group.new_reference("Assets.xcassets")
  app.resources_build_phase.add_file_reference(asset_catalog_ref)
end

resources_group = main_group.new_group("Resources", "Resources")
Dir[File.join(root, "STEWUniversity", "Resources", "**", "*.m4a")].sort.each do |path|
  ref = resources_group.new_reference(path.sub(File.join(root, "STEWUniversity", "Resources") + "/", ""))
  # Keep Xcode from probing every audio file just to infer its type. These files
  # are copied as opaque bundle resources and decoded by AVFoundation at runtime.
  ref.explicit_file_type = "file"
  app.resources_build_phase.add_file_reference(ref)
end

test_group = project.main_group.new_group("STEWUniversityTests", "STEWUniversityTests")
Dir[File.join(root, "STEWUniversityTests", "*.swift")].sort.each do |path|
  tests.source_build_phase.add_file_reference(test_group.new_reference(File.basename(path)))
end

ui_group = project.main_group.new_group("STEWUniversityUITests", "STEWUniversityUITests")
Dir[File.join(root, "STEWUniversityUITests", "*.swift")].sort.each do |path|
  ui_tests.source_build_phase.add_file_reference(ui_group.new_reference(File.basename(path)))
end

tests.add_dependency(app)
ui_tests.add_dependency(app)

app.build_configurations.each do |config|
  config.build_settings.merge!({
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.stewuniversity.ios",
    "PRODUCT_NAME" => "STEWUniversity",
    "SWIFT_VERSION" => "6.0",
    "TARGETED_DEVICE_FAMILY" => "1,2",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "INFOPLIST_FILE" => "STEWUniversity/Info.plist",
    "CODE_SIGN_ENTITLEMENTS" => "STEWUniversity/STEWUniversity.entitlements",
    "DEVELOPMENT_TEAM" => "6U4942H2Z8",
    "BAND_API_BASE_URL" => "https://stew-university-backend.onrender.com",
    "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
    "CODE_SIGN_STYLE" => "Automatic",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "AccentColor",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS" => "YES",
  })
  config.build_settings["APS_ENVIRONMENT"] = config.name == "Release" ? "production" : "development"
end

[[tests, "com.stewuniversity.ios.tests"], [ui_tests, "com.stewuniversity.ios.uitests"]].each do |target, bundle_id|
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      "PRODUCT_BUNDLE_IDENTIFIER" => bundle_id,
      "SWIFT_VERSION" => "6.0",
      "GENERATE_INFOPLIST_FILE" => "YES",
      "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/STEWUniversity.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/STEWUniversity",
      "BUNDLE_LOADER" => "$(TEST_HOST)",
      "CODE_SIGN_STYLE" => "Automatic",
    })
  end
end
ui_tests.build_configurations.each do |config|
  config.build_settings.delete("TEST_HOST")
  config.build_settings.delete("BUNDLE_LOADER")
  config.build_settings["TEST_TARGET_NAME"] = "STEWUniversity"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui_tests)
scheme.save_as(project_path, "STEWUniversityCI", true)
puts project_path
