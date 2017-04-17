function map_thumbnail(id, polyline) {
    var coordinates = decode(polyline);
    console.log(coordinates);
    var bounds = new google.maps.LatLngBounds();
    for (var i = 0; i < coordinates.length; i++) {
        bounds.extend(coordinates[i]);
    }
    console.log(id);
    var map = new google.maps.Map(document.getElementById(id));
    map.fitBounds(bounds);
        
    var decodedPath = google.maps.geometry.encoding.decodePath(polyline); 
    var setRegion = new google.maps.Polyline({
        path: decodedPath,
        strokeColor: "#FF0000",
        strokeOpacity: 1.0,
        strokeWeight: 2,
        map: map
    });
}

// source: http://doublespringlabs.blogspot.com.br/2012/11/decoding-polylines-from-google-maps.html
function decode(encoded){

    // array that holds the points

    var points=[ ]
    var index = 0, len = encoded.length;
    var lat = 0, lng = 0;
    while (index < len) {
        var b, shift = 0, result = 0;
        do {

    b = encoded.charAt(index++).charCodeAt(0) - 63;//finds ascii                                                                                    //and substract it by 63
              result |= (b & 0x1f) << shift;
              shift += 5;
             } while (b >= 0x20);


       var dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
       lat += dlat;
      shift = 0;
      result = 0;
     do {
        b = encoded.charAt(index++).charCodeAt(0) - 63;
        result |= (b & 0x1f) << shift;
       shift += 5;
         } while (b >= 0x20);
     var dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
     lng += dlng;
 
   points.push({lat:( lat / 1E5),lng:( lng / 1E5)})  
 
  }
  return points
}
