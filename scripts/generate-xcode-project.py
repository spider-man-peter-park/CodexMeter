#!/usr/bin/env python3
"""Generate a dependency-free Xcode app project bound to the local Swift package."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent

def ident(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def q(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = []
def obj(name, contents):
    key = ident(name)
    objects.append(f'{key} = {{ {contents} }};')
    return key

files, builds = [], []
for path in sorted((root / 'Sources/CodexMeterApp').glob('*.swift')):
    relative = path.relative_to(root).as_posix()
    files.append(obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(relative)}; sourceTree = SOURCE_ROOT;'))
    builds.append(obj('build:' + relative, f'isa = PBXBuildFile; fileRef = {files[-1]};'))
resourceBuilds = []
for path in sorted((root / 'Sources/CodexMeterApp/Resources').glob('*.png')):
    relative = path.relative_to(root).as_posix()
    files.append(obj(relative, f'isa = PBXFileReference; lastKnownFileType = image.png; path = {q(relative)}; sourceTree = SOURCE_ROOT;'))
    resourceBuilds.append(obj('build:' + relative, f'isa = PBXBuildFile; fileRef = {files[-1]};'))
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = CodexMeter.app; sourceTree = BUILT_PRODUCTS_DIR;')
package = obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
packageProduct = obj('packageProduct', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = CodexMeterCore;')
framework = obj('frameworkBuild', f'isa = PBXBuildFile; productRef = {packageProduct};')
sources = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework},); runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resourceBuilds)},); runOnlyForDeploymentPostprocessing = 0;')
products = obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = obj('group', f'isa = PBXGroup; children = ({",".join(files)},{products},); sourceTree = "<group>";')
projectConfigs, targetConfigs = [], []
for name in ['Debug', 'Release']:
    projectConfigs.append(obj('project:' + name, f'isa = XCBuildConfiguration; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; }}; name = {name};'))
    targetConfigs.append(obj('target:' + name, f'''isa = XCBuildConfiguration; buildSettings = {{
        PRODUCT_NAME = CodexMeter; PRODUCT_BUNDLE_IDENTIFIER = io.github.codexmeter.app;
        INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-";
        ENABLE_APP_SANDBOX = NO; SWIFT_OPTIMIZATION_LEVEL = {q('-Onone' if name == 'Debug' else '-O')};
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
    }}; name = {name};'''))
pc = obj('projectConfigs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectConfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = obj('targetConfigs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(targetConfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = CodexMeter; packageProductDependencies = ({packageProduct},); productName = CodexMeter; productReference = {product}; productType = "com.apple.product-type.application";')
project = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base,); mainGroup = {group}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
projectDir = root / 'CodexMeter.xcodeproj'
projectDir.mkdir(exist_ok=True)
(projectDir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
schemeDir = projectDir / 'xcshareddata/xcschemes'
schemeDir.mkdir(parents=True, exist_ok=True)
schemeDir.joinpath('CodexMeter.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CodexMeter.app" BlueprintName="CodexMeter" ReferencedContainer="container:CodexMeter.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CodexMeter.app" BlueprintName="CodexMeter" ReferencedContainer="container:CodexMeter.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated CodexMeter.xcodeproj')
