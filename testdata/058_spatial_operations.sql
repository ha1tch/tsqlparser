-- Sample 058: Geographic and Spatial Data Operations
-- Source: Microsoft Learn, MSSQLTips, Ed Katibah articles
-- Category: Reporting
-- Complexity: Advanced
-- Features: GEOGRAPHY, GEOMETRY, spatial indexes, distance calculations, geofencing

-- Find locations within radius
CREATE PROCEDURE dbo.FindLocationsWithinRadius
    @CenterLatitude FLOAT,
    @CenterLongitude FLOAT,
    @RadiusKm FLOAT,
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @LatColumn NVARCHAR(128) = 'Latitude',
    @LonColumn NVARCHAR(128) = 'Longitude'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @CenterPoint GEOGRAPHY;
    DECLARE @RadiusMeters FLOAT = @RadiusKm * 1000;
    
    -- Create center point
    SET @CenterPoint = GEOGRAPHY::Point(@CenterLatitude, @CenterLongitude, 4326);
    
    SET @SQL = N'
        SELECT 
            *,
            GEOGRAPHY::Point(' + QUOTENAME(@LatColumn) + ', ' + QUOTENAME(@LonColumn) + ', 4326).STDistance(@Center) / 1000.0 AS DistanceKm
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        WHERE ' + QUOTENAME(@LatColumn) + ' IS NOT NULL
          AND ' + QUOTENAME(@LonColumn) + ' IS NOT NULL
          AND GEOGRAPHY::Point(' + QUOTENAME(@LatColumn) + ', ' + QUOTENAME(@LonColumn) + ', 4326).STDistance(@Center) <= @Radius
        ORDER BY GEOGRAPHY::Point(' + QUOTENAME(@LatColumn) + ', ' + QUOTENAME(@LonColumn) + ', 4326).STDistance(@Center)';
    
    EXEC sp_executesql @SQL,
        N'@Center GEOGRAPHY, @Radius FLOAT',
        @Center = @CenterPoint,
        @Radius = @RadiusMeters;
END
GO

-- Calculate distance between two points
CREATE FUNCTION dbo.CalculateDistance
(
    @Lat1 FLOAT,
    @Lon1 FLOAT,
    @Lat2 FLOAT,
    @Lon2 FLOAT,
    @Unit NVARCHAR(10) = 'km'  -- km, miles, meters
)
RETURNS FLOAT
AS
BEGIN
    DECLARE @Point1 GEOGRAPHY = GEOGRAPHY::Point(@Lat1, @Lon1, 4326);
    DECLARE @Point2 GEOGRAPHY = GEOGRAPHY::Point(@Lat2, @Lon2, 4326);
    DECLARE @DistanceMeters FLOAT = @Point1.STDistance(@Point2);
    
    RETURN CASE @Unit
        WHEN 'km' THEN @DistanceMeters / 1000.0
        WHEN 'miles' THEN @DistanceMeters / 1609.344
        WHEN 'meters' THEN @DistanceMeters
        ELSE @DistanceMeters / 1000.0
    END;
END
GO

-- Check if point is within polygon (geofencing)
CREATE PROCEDURE dbo.CheckPointInGeofence
    @Latitude FLOAT,
    @Longitude FLOAT,
    @GeofenceWKT NVARCHAR(MAX),  -- Well-Known Text polygon
    @IsInside BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Point GEOGRAPHY;
    DECLARE @Geofence GEOGRAPHY;
    
    SET @Point = GEOGRAPHY::Point(@Latitude, @Longitude, 4326);
    SET @Geofence = GEOGRAPHY::STGeomFromText(@GeofenceWKT, 4326);
    
    SET @IsInside = @Geofence.STIntersects(@Point);
    
    SELECT 
        @IsInside AS IsInsideGeofence,
        @Point.STDistance(@Geofence.STBoundary()) / 1000.0 AS DistanceToEdgeKm;
END
GO

-- Find nearest N locations
CREATE PROCEDURE dbo.FindNearestLocations
    @Latitude FLOAT,
    @Longitude FLOAT,
    @TopN INT = 10,
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @GeoColumn NVARCHAR(128) = NULL,  -- If table has GEOGRAPHY column
    @LatColumn NVARCHAR(128) = 'Latitude',
    @LonColumn NVARCHAR(128) = 'Longitude'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SearchPoint GEOGRAPHY = GEOGRAPHY::Point(@Latitude, @Longitude, 4326);
    
    IF @GeoColumn IS NOT NULL
    BEGIN
        -- Use existing geography column
        SET @SQL = N'
            SELECT TOP (@N)
                *,
                ' + QUOTENAME(@GeoColumn) + '.STDistance(@Point) / 1000.0 AS DistanceKm
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@GeoColumn) + ' IS NOT NULL
            ORDER BY ' + QUOTENAME(@GeoColumn) + '.STDistance(@Point)';
    END
    ELSE
    BEGIN
        -- Calculate from lat/lon columns
        SET @SQL = N'
            SELECT TOP (@N)
                *,
                GEOGRAPHY::Point(' + QUOTENAME(@LatColumn) + ', ' + QUOTENAME(@LonColumn) + ', 4326).STDistance(@Point) / 1000.0 AS DistanceKm
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@LatColumn) + ' IS NOT NULL 
              AND ' + QUOTENAME(@LonColumn) + ' IS NOT NULL
            ORDER BY GEOGRAPHY::Point(' + QUOTENAME(@LatColumn) + ', ' + QUOTENAME(@LonColumn) + ', 4326).STDistance(@Point)';
    END
    
    EXEC sp_executesql @SQL,
        N'@N INT, @Point GEOGRAPHY',
        @N = @TopN,
        @Point = @SearchPoint;
END
GO

-- Create spatial index on table
CREATE PROCEDURE dbo.CreateSpatialIndex
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @GeoColumn NVARCHAR(128),
    @IndexType NVARCHAR(20) = 'GEOGRAPHY'  -- GEOGRAPHY or GEOMETRY
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @IndexName NVARCHAR(128) = 'SIX_' + @TableName + '_' + @GeoColumn;
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Drop existing index
    IF EXISTS (SELECT 1 FROM sys.spatial_indexes WHERE name = @IndexName)
    BEGIN
        SET @SQL = 'DROP INDEX ' + QUOTENAME(@IndexName) + ' ON ' + @FullPath;
        EXEC sp_executesql @SQL;
    END
    
    -- Create spatial index
    IF @IndexType = 'GEOGRAPHY'
    BEGIN
        SET @SQL = '
            CREATE SPATIAL INDEX ' + QUOTENAME(@IndexName) + '
            ON ' + @FullPath + '(' + QUOTENAME(@GeoColumn) + ')
            USING GEOGRAPHY_AUTO_GRID
            WITH (CELLS_PER_OBJECT = 16)';
    END
    ELSE
    BEGIN
        SET @SQL = '
            CREATE SPATIAL INDEX ' + QUOTENAME(@IndexName) + '
            ON ' + @FullPath + '(' + QUOTENAME(@GeoColumn) + ')
            USING GEOMETRY_AUTO_GRID
            WITH (CELLS_PER_OBJECT = 16)';
    END
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Spatial index created: ' + @IndexName AS Status;
END
GO

-- Calculate polygon area and perimeter
CREATE PROCEDURE dbo.CalculatePolygonMetrics
    @PolygonWKT NVARCHAR(MAX),
    @GeographyType NVARCHAR(20) = 'GEOGRAPHY'  -- GEOGRAPHY or GEOMETRY
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @GeographyType = 'GEOGRAPHY'
    BEGIN
        DECLARE @Geog GEOGRAPHY = GEOGRAPHY::STGeomFromText(@PolygonWKT, 4326);
        
        SELECT 
            @Geog.STArea() / 1000000.0 AS AreaSquareKm,
            @Geog.STLength() / 1000.0 AS PerimeterKm,
            @Geog.STNumPoints() AS NumPoints,
            @Geog.STCentroid().Lat AS CentroidLatitude,
            @Geog.STCentroid().Long AS CentroidLongitude;
    END
    ELSE
    BEGIN
        DECLARE @Geom GEOMETRY = GEOMETRY::STGeomFromText(@PolygonWKT, 0);
        
        SELECT 
            @Geom.STArea() AS Area,
            @Geom.STLength() AS Perimeter,
            @Geom.STNumPoints() AS NumPoints,
            @Geom.STCentroid().STX AS CentroidX,
            @Geom.STCentroid().STY AS CentroidY;
    END
END
GO

-- Find overlapping regions
CREATE PROCEDURE dbo.FindOverlappingRegions
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @GeoColumn NVARCHAR(128),
    @IdColumn NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        SELECT 
            a.' + QUOTENAME(@IdColumn) + ' AS Region1ID,
            b.' + QUOTENAME(@IdColumn) + ' AS Region2ID,
            a.' + QUOTENAME(@GeoColumn) + '.STIntersection(b.' + QUOTENAME(@GeoColumn) + ').STArea() AS OverlapArea,
            a.' + QUOTENAME(@GeoColumn) + '.STIntersection(b.' + QUOTENAME(@GeoColumn) + ').ToString() AS OverlapWKT
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' a
        INNER JOIN ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' b
            ON a.' + QUOTENAME(@IdColumn) + ' < b.' + QUOTENAME(@IdColumn) + '
            AND a.' + QUOTENAME(@GeoColumn) + '.STIntersects(b.' + QUOTENAME(@GeoColumn) + ') = 1
        ORDER BY OverlapArea DESC';
    
    EXEC sp_executesql @SQL;
END
GO
