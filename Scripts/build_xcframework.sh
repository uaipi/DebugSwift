#!/bin/bash

# DebugSwift XCFramework Build Script
# This script builds DebugSwift as an XCFramework with support for:
# - iOS Device (arm64)
# - iOS Simulator (arm64, x86_64)

set -e

# Configuration
FRAMEWORK_NAME="DebugSwift"
PROJECT_NAME="DebugSwift"
SCHEME_NAME="DebugSwift"
BUILD_DIR="$(pwd)/build"
XCFRAMEWORK_DIR="$(pwd)/XCFramework"
DERIVED_DATA_DIR="$(pwd)/DerivedData"
ROOT_DIR="$(pwd)"
PACKAGE_DIR="$(pwd)/build/xcframework-package"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to clean up previous builds
cleanup() {
    print_status "Cleaning up previous builds..."
    rm -rf "${BUILD_DIR:?}"
    rm -rf "${XCFRAMEWORK_DIR:?}"
    rm -rf "${DERIVED_DATA_DIR:?}"
}

# Function to create directories
create_directories() {
    print_status "Creating build directories..."
    mkdir -p "$BUILD_DIR"
    mkdir -p "$XCFRAMEWORK_DIR"
}

# SwiftPM only builds a real .framework for a dynamic product, and the root package keeps its
# libraries on automatic linkage. This helper package compiles DebugSwift and DebugSwiftCore into
# one dynamic DebugSwift module (the layout the CocoaPods spec uses), so a single framework carries
# both and the canImport guard skips `@_exported import DebugSwiftCore`.
create_framework_package() {
    print_status "Creating the framework package..."
    mkdir -p "$PACKAGE_DIR/Sources/DebugSwift"
    ln -s "$ROOT_DIR/DebugSwift/Sources" "$PACKAGE_DIR/Sources/DebugSwift/DebugSwiftSources"
    ln -s "$ROOT_DIR/DebugSwiftCore/Sources/DebugSwiftCore" "$PACKAGE_DIR/Sources/DebugSwift/DebugSwiftCoreSources"
    ln -s "$ROOT_DIR/DebugSwift/Resources" "$PACKAGE_DIR/Sources/DebugSwift/Resources"
    cat > "$PACKAGE_DIR/Package.swift" << 'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DebugSwift",
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "DebugSwift", type: .dynamic, targets: ["DebugSwift"])
    ],
    targets: [
        .target(
            name: "DebugSwift",
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageModes: [.v6]
)
EOF
    print_success "Framework package created"
}

# Function to build framework for a specific destination using Swift Package Manager
build_framework() {
    local destination=$1
    local sdk=$2
    local arch=$3
    local output_dir="$BUILD_DIR/$arch-$sdk"
    
    print_status "Building $FRAMEWORK_NAME for $destination ($arch)..."
    
    # Build the dynamic framework package with xcodebuild
    (cd "$PACKAGE_DIR" && xcodebuild -scheme "$FRAMEWORK_NAME" \
               -destination "$destination" \
               -configuration Release \
               -sdk "$sdk" \
               -derivedDataPath "$DERIVED_DATA_DIR" \
               -skipPackagePluginValidation \
               ARCHS="$arch" \
               VALID_ARCHS="$arch" \
               ONLY_ACTIVE_ARCH=NO \
               BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
               SKIP_INSTALL=NO \
               CONFIGURATION_BUILD_DIR="$output_dir" \
               build) || {
        print_error "Failed to build for $destination"
        exit 1
    }

    # SwiftPM places the framework in PackageFrameworks and the Swift module beside it.
    local built_framework="$output_dir/PackageFrameworks/$FRAMEWORK_NAME.framework"
    local built_module="$output_dir/$FRAMEWORK_NAME.swiftmodule"
    if [[ ! -d "$built_framework" || ! -d "$built_module" ]]; then
        print_error "Could not find the built framework or module for $arch-$sdk in $output_dir"
        exit 1
    fi

    # A slice needs its Swift module inside the framework so consumers can import it.
    cp -R "$built_framework" "$output_dir/$FRAMEWORK_NAME.framework"
    mkdir -p "$output_dir/$FRAMEWORK_NAME.framework/Modules"
    cp -R "$built_module" "$output_dir/$FRAMEWORK_NAME.framework/Modules/$FRAMEWORK_NAME.swiftmodule"

    print_success "Successfully built for $destination ($arch)"
}

# Function to create XCFramework
create_xcframework() {
    print_status "Creating XCFramework..."
    
    # Check if frameworks exist
    local ios_device_framework="$BUILD_DIR/arm64-iphoneos/$FRAMEWORK_NAME.framework"
    local ios_simulator_framework="$BUILD_DIR/arm64_x86_64-iphonesimulator/$FRAMEWORK_NAME.framework"
    
    if [[ ! -d "$ios_device_framework" ]]; then
        print_error "iOS device framework not found at $ios_device_framework"
        exit 1
    fi
    
    if [[ ! -d "$ios_simulator_framework" ]]; then
        print_error "iOS simulator framework not found at $ios_simulator_framework"
        exit 1
    fi
    
    # Create XCFramework
    xcodebuild -create-xcframework \
               -framework "$ios_device_framework" \
               -framework "$ios_simulator_framework" \
               -output "$XCFRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create XCFramework"
        exit 1
    fi
    
    print_success "XCFramework created successfully at $XCFRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
}

# Function to validate XCFramework
validate_xcframework() {
    print_status "Validating XCFramework..."
    
    local xcframework_path="$XCFRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
    
    if [[ ! -d "$xcframework_path" ]]; then
        print_error "XCFramework not found at $xcframework_path"
        exit 1
    fi
    
    # Check Info.plist exists
    if [[ ! -f "$xcframework_path/Info.plist" ]]; then
        print_error "Info.plist not found in XCFramework"
        exit 1
    fi
    
    # List architectures
    print_status "XCFramework architectures:"
    find "$xcframework_path" -name "*.framework" | while read framework; do
        echo "  Framework: $(basename "$framework")"
        if [[ -f "$framework/$FRAMEWORK_NAME" ]]; then
            echo "    Architectures: $(lipo -archs "$framework/$FRAMEWORK_NAME" 2>/dev/null || echo "Unknown")"
        fi
    done
    
    print_success "XCFramework validation completed"
}

# Function to create zip archive
create_archive() {
    print_status "Creating ZIP archive..."
    
    cd "$XCFRAMEWORK_DIR"
    zip -r "${FRAMEWORK_NAME}.xcframework.zip" "${FRAMEWORK_NAME}.xcframework"
    cd - > /dev/null
    
    print_success "ZIP archive created at $XCFRAMEWORK_DIR/${FRAMEWORK_NAME}.xcframework.zip"
}

# Main execution
main() {
    print_status "Starting DebugSwift XCFramework build process..."
    print_status "Framework: $FRAMEWORK_NAME"
    print_status "Build directory: $BUILD_DIR"
    print_status "Output directory: $XCFRAMEWORK_DIR"
    
    # Check if we're in the right directory
    if [[ ! -f "Package.swift" ]]; then
        print_error "Package.swift not found. Please run this script from the project root directory."
        exit 1
    fi
    
    cleanup
    create_directories
    create_framework_package

    # Build for iOS Device (arm64)
    build_framework "generic/platform=iOS" "iphoneos" "arm64"
    
    # Build for iOS Simulator (arm64 + x86_64 universal)
    print_status "Building universal simulator framework..."
    
    # Build arm64 simulator
    build_framework "generic/platform=iOS Simulator" "iphonesimulator" "arm64"
    
    # Build x86_64 simulator  
    build_framework "generic/platform=iOS Simulator" "iphonesimulator" "x86_64"
    
    # Create universal simulator framework
    print_status "Creating universal simulator framework..."
    local arm64_sim="$BUILD_DIR/arm64-iphonesimulator/$FRAMEWORK_NAME.framework"
    local x86_64_sim="$BUILD_DIR/x86_64-iphonesimulator/$FRAMEWORK_NAME.framework"
    local universal_sim="$BUILD_DIR/arm64_x86_64-iphonesimulator/$FRAMEWORK_NAME.framework"
    
    # Copy arm64 framework as base
    mkdir -p "$(dirname "$universal_sim")"
    cp -R "$arm64_sim" "$universal_sim"
    
    # Create universal binary
    lipo -create \
         "$arm64_sim/$FRAMEWORK_NAME" \
         "$x86_64_sim/$FRAMEWORK_NAME" \
         -output "$universal_sim/$FRAMEWORK_NAME"
    
    # The universal slice needs the Swift module files of both architectures
    cp -R "$x86_64_sim/Modules/$FRAMEWORK_NAME.swiftmodule/." "$universal_sim/Modules/$FRAMEWORK_NAME.swiftmodule/"

    print_success "Universal simulator framework created"
    
    create_xcframework
    validate_xcframework
    create_archive
    
    print_success "DebugSwift XCFramework build completed successfully!"
    print_status "XCFramework location: $XCFRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"
    print_status "ZIP archive location: $XCFRAMEWORK_DIR/${FRAMEWORK_NAME}.xcframework.zip"
}

# Execute main function
main "$@"
