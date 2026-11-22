#Requires -Version 7.5
[CmdletBinding()]
param([string]$Source=(Join-Path $PSScriptRoot '../assets/remnexa-logo.png'),[string]$Output=(Join-Path $PSScriptRoot '../assets/icons/remnexa.ico'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$sourceImage=[Drawing.Bitmap]::new([IO.Path]::GetFullPath($Source))
$frames=[Collections.Generic.List[byte[]]]::new()
try {
    $left=$sourceImage.Width;$top=$sourceImage.Height;$right=0;$bottom=0
    for($y=0;$y -lt $sourceImage.Height;$y++){for($x=0;$x -lt $sourceImage.Width;$x++){if($sourceImage.GetPixel($x,$y).A -gt 32){$left=[Math]::Min($left,$x);$top=[Math]::Min($top,$y);$right=[Math]::Max($right,$x);$bottom=[Math]::Max($bottom,$y)}}}
    if($right -le $left -or $bottom -le $top){throw 'Logo has no visible image.'}
    $bounds=[Drawing.Rectangle]::new($left,$top,$right-$left+1,$bottom-$top+1)
    $sizes=@(16,24,32,48,64,128,256)
    foreach($size in $sizes){
        $bitmap=[Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bitmap);$memory=[IO.MemoryStream]::new()
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $scale=($size*0.9)/[Math]::Max($bounds.Width,$bounds.Height)
            $w=[single]($bounds.Width*$scale);$h=[single]($bounds.Height*$scale)
            $graphics.DrawImage($sourceImage,[Drawing.RectangleF]::new(($size-$w)/2,($size-$h)/2,$w,$h),$bounds,[Drawing.GraphicsUnit]::Pixel)
            $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png);$frames.Add($memory.ToArray())
        }finally{$graphics.Dispose();$bitmap.Dispose();$memory.Dispose()}
    }
    $full=[IO.Path]::GetFullPath($Output);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
    $writer=[IO.BinaryWriter]::new([IO.File]::Create($full))
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$sizes.Count)
        $offset=6+16*$sizes.Count
        for($i=0;$i -lt $sizes.Count;$i++){
            $value=if($sizes[$i] -eq 256){0}else{$sizes[$i]}
            $writer.Write([byte]$value);$writer.Write([byte]$value);$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$frames[$i].Length);$writer.Write([uint32]$offset);$offset+=$frames[$i].Length
        }
        foreach($frame in $frames){$writer.Write($frame)}
    }finally{$writer.Dispose()}
    Get-Item -LiteralPath $full|Select-Object FullName,Length
}finally{$sourceImage.Dispose()}
