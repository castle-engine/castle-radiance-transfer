{
  Copyright 2008-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Simple Precomputed Radiance Transfer implementation.
  Self-shadowing with diffuse lighting.

  Navigate with mouse or keyboard (like view3dscene in Examine mode).

  AWSD, QE move the light.
  R, Shift+R change light radius.
  L, Shift+L change light intensity scale.
}
unit RadianceTransferMain;

interface

implementation

uses SysUtils, Classes, Math,
  CastleVectors, X3DNodes, CastleWindow, CastleShapes,
  CastleClassUtils, CastleUtils, CastleCameras, CastleUiControls,
  CastleGLUtils, CastleScene, CastleKeysMouse, CastleViewport,
  CastleFilesUtils, CastleLog, CastleInternalSphericalHarmonics, CastleImages,
  CastleInternalGLCubeMaps, CastleStringUtils, CastleParameters, CastleColors,
  CastleApplicationProperties, CastleControls, CastleTransform, X3DFields,
  SceneUtilities;

type
  TViewMode = (vmNormal, vmSimpleOcclusion, vmFull);

var
  Window: TCastleWindow;
  Scene: TCastleScene;
  SceneLightVisualize, SceneLightVisualizeForMap: TCastleScene;
  MaterialLight, MaterialLightForMap: TUnlitMaterialNode;
  SphereLight, SphereLightForMap: TSphereNode;
  ViewMode: TViewMode = vmFull;
  LightRadius: Single;
  LightPos: TVector3;

const
  { This is currently not synched with actual SHBasisCount used to generate
    the Scene. We just always prepare LightSHBasisCount components,
    eventually some of them will not be used in DoRadianceTransfer.

    While this is not optimal, this also may allow to use different SHBasis
    for different shapes within the Scene in the future. }

  LightSHBasisCount = 25;

var
  { This is calculated at the beginning of each Draw.
    Can be used then by DoRadianceTransfer. }
  LightSHBasis: array [0..LightSHBasisCount - 1] of Single;

  { Intensity specific for this light.
    Right now, we have only one light here, but the point is that we could
    have any number of lights.
    Only in 0..1 (as it's used as color component). }
  LightIntensity: Single = 1.0;

  { All lights intensity (obtained by getting light maps) are scaled
    by this. Can be in any range. }
  LightIntensityScale: Single = 100.0;

type
  TMyViewport = class(TCastleViewport)
  strict private
    function VertexColor(const Shape: TShape; const VertexPosition: TVector3;
      const VertexIndex: Integer): TCastleColorRGB;
    procedure DrawLight(const RenderParams: TRenderParams);
  public
    procedure Render; override;
  end;

procedure TMyViewport.DrawLight(const RenderParams: TRenderParams);
begin
  SceneLightVisualizeForMap.Render(RenderParams);
end;

function TMyViewport.VertexColor(const Shape: TShape; const VertexPosition: TVector3;
  const VertexIndex: Integer): TCastleColorRGB;
var
  Geometry: TAbstractGeometryNode;
  State: TX3DGraphTraverseState;
  I: Integer;
  RadianceTransferPtr: TVector3List.PtrT;
  RadianceTransferList: TVector3List;
  Coord: TMFVec3f;
  RadianceTransferVertexSize: Cardinal;
begin
  Geometry := Shape.OriginalGeometry;
  State := Shape.OriginalState;
  Result := WhiteRGB; // default result, in case of error

  // calculate RadianceTransferList
  if not (Geometry is TAbstractComposedGeometryNode) then
    Exit;
  RadianceTransferList := (Geometry as TAbstractComposedGeometryNode).FdRadianceTransfer.Items;

  if not Geometry.InternalCoord(State, Coord) then
    Exit;

  // check RadianceTransferList
  if RadianceTransferList <> nil then
  begin
    if RadianceTransferList.Count = 0 then
    begin
      WritelnWarning('X3D', 'radianceTransfer field empty');
      Exit;
    end;

    if RadianceTransferList.Count mod Coord.Count <> 0 then
    begin
      WritelnWarning('X3D', 'radianceTransfer must have a number of items being multiple of coods');
      Exit;
    end;

    if RadianceTransferList.Count < Coord.Count then
    begin
      WritelnWarning('X3D', 'radianceTransfer must have a number of items >= number of coods');
      Exit;
    end;
  end;

  // calculate RadianceTransferVertexSize
  RadianceTransferVertexSize := RadianceTransferList.Count div Coord.Count;
  Assert(RadianceTransferVertexSize > 0);

  RadianceTransferPtr := RadianceTransferList.Ptr(VertexIndex * RadianceTransferVertexSize);

  if ViewMode = vmSimpleOcclusion then
  begin
    Result := RadianceTransferPtr[0];
  end else
  begin
    Result := TVector3.Zero;
    for I := 0 to Min(RadianceTransferVertexSize, LightSHBasisCount) - 1 do
    begin
      Result.X := Result.X + RadianceTransferPtr[I].X * LightSHBasis[I];
      Result.Y := Result.Y + RadianceTransferPtr[I].Y * LightSHBasis[I];
      Result.Z := Result.Z + RadianceTransferPtr[I].Z * LightSHBasis[I];
    end;
  end;
end;

procedure TMyViewport.Render;
begin
  { update light visualization (for normal display and for SHVectorGLCapture texture rendering) }
  SceneLightVisualize.Translation := LightPos;
  SceneLightVisualizeForMap.Translation := LightPos;
  MaterialLightForMap.EmissiveColor := Vector3(LightIntensity, LightIntensity, LightIntensity);
  SphereLight.Radius := LightRadius;
  SphereLightForMap.Radius := LightRadius;

  if not Scene.BoundingBox.IsEmpty then
  begin
    { SHVectorGLCapture wil draw maps, get them,
      and calculate LightSHBasis describing the light contribution
      (this will be used then by Scene.Render, during DoRadianceTransfer). }

    SHVectorGLCapture(LightSHBasis, Scene.BoundingBox.Center,
      {$ifdef FPC}@{$endif} DrawLight, 100, 100, LightIntensityScale);

    { no need to reset RenderContext.Viewport
      inherited TCastleViewport.Render calls
      ApplyProjection that will already do it. }
  end;

  if ViewMode = vmNormal then
    RemoveSceneColors(Scene)
  else
    SetSceneColors(Scene, {$ifdef FPC}@{$endif} VertexColor);

  inherited;
end;

{ TMyView --------------------------------------------------------------------- }

type
  { View to contain whole UI and to handle events, like update and menu clicks. }
  TMyView = class(TCastleView)
  private
    Viewport: TMyViewport;
    procedure MenuItemClick(const Item: TMenuItem);
  public
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: boolean); override;
  end;

var
  MyView: TMyView;

procedure TMyView.Start;

  function CreateLightVisualizeNodes(out Material: TUnlitMaterialNode; out Sphere: TSphereNode): TX3DRootNode;
  var
    SphereShape: TShapeNode;
    Appearance: TAppearanceNode;
  begin
    Result := TX3DRootNode.Create;

    Sphere := TSphereNode.CreateWithShape(SphereShape);
    Result.AddChildren(SphereShape);

    Material := TUnlitMaterialNode.Create;

    Appearance := TAppearanceNode.Create;
    Appearance.Material := Material;

    SphereShape.Appearance := Appearance;
  end;

var
  URL: string;
  Background: TCastleRectangleControl;
  Navigation: TCastleExamineNavigation;
begin
  inherited;

  Parameters.CheckHighAtMost(1);
  if Parameters.High = 1 then
    URL := Parameters[1]
  else
    URL := 'castle-data:/chinchilla_with_prt.wrl.gz';

  Scene := TCastleScene.Create(Application);
  Scene.Load(URL);

  SceneLightVisualize := TCastleScene.Create(Application);
  SceneLightVisualize.Load(CreateLightVisualizeNodes(MaterialLight, SphereLight), true);
  MaterialLight.EmissiveColor := YellowRGB;
  MaterialLight.Transparency := 0.9;

  SceneLightVisualizeForMap := TCastleScene.Create(Application);
  SceneLightVisualizeForMap.Load(CreateLightVisualizeNodes(MaterialLightForMap, SphereLightForMap), true);

  if Scene.BoundingBox.IsEmpty then
  begin
    LightRadius := 1;
    LightPos := Vector3(2, 0, 0);
  end else
  begin
    LightRadius := Scene.BoundingBox.AverageSize;
    LightPos := Scene.BoundingBox.Center;
    LightPos.X :=
      LightPos.X +
      ( Scene.BoundingBox.Data[1].X -
        Scene.BoundingBox.Data[0].X + LightRadius );
  end;

  Background := TCastleRectangleControl.Create(Application);
  Background.FullSize := true;
  Background.Color := Black;
  Window.Controls.InsertFront(Background);

  Navigation := TCastleExamineNavigation.Create(Application);

  Viewport := TMyViewport.Create(Application);
  Viewport.FullSize := true;
  Viewport.AutoCamera := true;
  Viewport.InsertBack(Navigation);
  { we will clear context by our own Background,
    to keep SHVectorGLCapture visible for debugging }
  Viewport.Transparent := true;
  Viewport.Items.Add(Scene);
  Viewport.Items.Add(SceneLightVisualize);
  Viewport.Items.MainScene := Scene;

  { Our viewport contains large sphere (to visualize light source),
    ignore it for Examine rotation pivot,
    always rotate around point 0. }
  Navigation.AutoCenterOfRotation := false;
  Navigation.CenterOfRotation := TVector3.Zero;

  MyView := TMyView.Create(Application);
  MyView.Viewport := Viewport;

  InsertFront(Viewport);

  InitializeSHBasisMap;

  Window.OnMenuItemClick := {$ifdef FPC}@{$endif} MenuItemClick;
end;

procedure TMyView.Stop;
begin
  Window.OnMenuItemClick := nil;
  inherited;
end;

procedure TMyView.MenuItemClick(const Item: TMenuItem);
begin
  case Item.IntData of
    10: ViewMode := vmNormal;
    11: ViewMode := vmSimpleOcclusion;
    12: ViewMode := vmFull;
    20: with Scene.RenderOptions do Lighting := not Lighting;
    100: Container.SaveScreenToDefaultFile;
    200: Window.Close;
    else Exit;
  end;
end;

procedure TMyView.Update(const SecondsPassed: Single; var HandleInput: boolean);

  procedure ChangeLightPosition(Coord, Change: Integer);
  begin
    LightPos.Data[Coord] := LightPos.Data[Coord] +
     Change * SecondsPassed *
      { scale by Box3DAvgSize, to get similar move on all models }
      Scene.BoundingBox.AverageSize;
  end;

  procedure ChangeLightRadius(Change: Float);
  begin
    LightRadius := LightRadius * Power(Change, SecondsPassed);
  end;

  procedure ChangeLightIntensityScale(Change: Float);
  begin
    LightIntensityScale :=
      LightIntensityScale * Power(Change, SecondsPassed);
  end;

begin
  inherited;

  if Container.Pressed[keyA] then ChangeLightPosition(0, -1);
  if Container.Pressed[keyD] then ChangeLightPosition(0,  1);
  if Container.Pressed[keyS] then ChangeLightPosition(2, -1);
  if Container.Pressed[keyW] then ChangeLightPosition(2,  1);
  if Container.Pressed[keyQ] then ChangeLightPosition(1, -1);
  if Container.Pressed[keyE] then ChangeLightPosition(1,  1);

  if Container.Pressed[keyR] then
  begin
    if mkShift in Container.Pressed.Modifiers then
      ChangeLightRadius(1/1.8)
    else
      ChangeLightRadius(1.8);
  end;

  if Container.Pressed[keyL] then
  begin
    if mkShift in Container.Pressed.Modifiers then
      ChangeLightIntensityScale(1/1.5)
    else
      ChangeLightIntensityScale(1.5);
  end;
end;

function CreateMainMenu: TMenu;
var
  M: TMenu;
  Radio: TMenuItemRadio;
  RadioGroup: TMenuItemRadioGroup;
begin
  Result := TMenu.Create('Main menu');
  M := TMenu.Create('_Program');

    Radio := TMenuItemRadio.Create('_Normal (no PRT)', 10, ViewMode = vmNormal, true);
    RadioGroup := Radio.Group;
    M.Append(Radio);

    Radio := TMenuItemRadio.Create('_Simple Occlusion', 11, ViewMode = vmSimpleOcclusion, true);
    Radio.Group := RadioGroup;
    M.Append(Radio);

    Radio := TMenuItemRadio.Create('_Full Radiance Transfer', 12, ViewMode = vmFull, true);
    Radio.Group := RadioGroup;
    M.Append(Radio);

    M.Append(TMenuSeparator.Create);
    M.Append(TMenuItemChecked.Create('Use Normal _Lighting', 20, { Scene.RenderOptions.Lighting } true, true));
    M.Append(TMenuSeparator.Create);
    M.Append(TMenuItem.Create('_Save Screen ...', 100, keyF5));
    M.Append(TMenuSeparator.Create);
    M.Append(TMenuItem.Create('_Exit', 200));
    Result.Append(M);
end;

{ One-time initialization of resources. }
procedure ApplicationInitialize;
begin
  MyView := TMyView.Create(Application);
  Window.Container.View := MyView;
end;

initialization
  { Set ApplicationName early, as our log uses it.
    Optionally you could also set ApplicationProperties.Version here. }
  ApplicationProperties.ApplicationName := 'radiance_transfer';

  { Start logging. Do this as early as possible,
    to log information and eventual warnings during initialization. }
  InitializeLog;

  { Initialize Application.OnInitialize. }
  Application.OnInitialize := @ApplicationInitialize;

  { Create and assign Application.MainWindow. }
  Window := TCastleWindow.Create(Application);
  Application.MainWindow := Window;
  Window.MainMenu := CreateMainMenu;
end.
