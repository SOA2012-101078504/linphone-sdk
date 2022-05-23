# Uncomment the next line to define a global platform for your project
platform :ios, '10.0'

target 'LinphoneTester' do
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!

  # Pods for LinphoneTester
if ENV['PODFILE_PATH'].nil?
    pod 'linphone-sdk/swift', :path => "@LINPHONESDK_BUILD_DIR@/"
else
    pod 'linphone-sdk/swift', :path => ENV['PODFILE_PATH']  # local sdk
end


  target 'LinphoneTesterTests' do
    inherit! :search_paths
    # Pods for testing
  end

end
