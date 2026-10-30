#pragma once

#include "CoreMinimal.h"
#include "SwordPartActor.h"
#include "SwordPartStaticMeshActor.generated.h"

// Intentionally no mirrored properties/components.
// The real Bladesong class owns its actual SwordPart machinery.
UCLASS(Blueprintable, BlueprintType)
class BLADESONG_API ASwordPartStaticMeshActor : public ASwordPartActor
{
    GENERATED_BODY()
};
