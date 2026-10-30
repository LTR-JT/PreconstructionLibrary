using UnrealBuildTool;
using System.Collections.Generic;

public class BladesongEditorTarget : TargetRules
{
    public BladesongEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("Bladesong");
    }
}
