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

{ Main view, where most of the application logic takes place. }
unit GameViewMain;

interface

uses Classes,
  CastleVectors, CastleComponentSerialize, CastleViewport, CastleScene,
  CastleUIControls, CastleControls, CastleKeysMouse,
  CastleShapes, CastleTransform, CastleColors;

type
  { Main view, where most of the application logic takes place. }
  TViewMain = class(TCastleView)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelFps, LabelShReport: TCastleLabel;
    MainViewport: TCastleViewport;
  private
    type
      { Render 3D sphere that visualizes spherical harmonics. }
      TMyShVisualization = class(TCastleScene)
      private
        function VertexColor(
          const Shape: TShape;
          const VertexPosition: TVector3;
          const VertexIndex: Integer): TCastleColorRGB;
      public
        { Spherical harmonics to display. }
        LM: Cardinal;
        { Updated by this class in each render, read-only from outside. }
        MinSHValue, MaxSHValue: Single;
        constructor Create(AOwner: TComponent); override;
        procedure LocalRender(const Params: TRenderParams); override;
      end;
    var
      ShVisualization: TMyShVisualization;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMain: TViewMain;

implementation

uses SysUtils, Math,
  CastleInternalSphericalHarmonics, CastleInternalSphereSampling,
  CastleUtils,
  SceneUtilities;

{ TMyShVisualization ------------------------------------------------------------------ }

function TViewMain.TMyShVisualization.VertexColor(
  const Shape: TShape;
  const VertexPosition: TVector3;
  const VertexIndex: Integer): TCastleColorRGB;
var
  SH: Single;
begin
  SH := SHBasis(LM, XYZToPhiTheta(VertexPosition));
  if SH > MaxSHValue then MaxSHValue := SH;
  if SH < MinSHValue then MinSHValue := SH;

  if SH >= 0 then
    Result := Vector3(SH, SH, 0)
  else
    Result := Vector3(0, 0, -SH);
end;

constructor TViewMain.TMyShVisualization.Create(AOwner: TComponent);
begin
  inherited;

  { Load a scene with sphere.

    Why not using TSphereNode?
    Because our SetSceneColor doesn't support changing colors on TSphereNode. }
  Load('castle-data:/sphere.gltf');
end;

procedure TViewMain.TMyShVisualization.LocalRender(const Params: TRenderParams);
begin
  { before every rendering clear Min/MaxSHValue, so that VertexColor can set them }
  MinSHValue :=  MaxFloat;
  MaxSHValue := -MaxFloat;
  SetSceneColors(Self, {$ifdef FPC}@{$endif}VertexColor);
  inherited;
end;

{ TViewMain ----------------------------------------------------------------- }

constructor TViewMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
end;

procedure TViewMain.Start;
begin
  inherited;
  ShVisualization := TMyShVisualization.Create(FreeAtStop);
  MainViewport.Items.Add(ShVisualization);
end;

procedure TViewMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  L: Cardinal;
  M: Integer;
begin
  inherited;
  { This virtual method is executed every frame (many times per second). }

  Assert(LabelFps <> nil, 'If you remove LabelFps from the design, remember to remove also the assignment "LabelFps.Caption := ..." from code');
  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;

  LMDecode(ShVisualization.LM, L, M);
  LabelShReport.Caption := Format('Spherical harmonic number %d. (L, M) = (%d, %d). Results in range (%f, %f)', [
    ShVisualization.LM,
    L,
    M,
    ShVisualization.MinSHValue,
    ShVisualization.MaxSHValue
  ]);
end;

function TViewMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(keyN) then
  begin
    ShVisualization.LM := ChangeIntCycle(ShVisualization.LM, +1, MaxSHBasis - 1);
    { ShVisualization.Min/MaxSHValue will be automatically updated
      at next render.}
    Exit(true); // key was handled
  end;

  if Event.IsKey(keyP) then
  begin
    ShVisualization.LM := ChangeIntCycle(ShVisualization.LM, -1, MaxSHBasis - 1);
    { ShVisualization.Min/MaxSHValue will be automatically updated
      at next render.}
    Exit(true); // key was handled
  end;
end;

end.
