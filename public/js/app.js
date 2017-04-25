/**
 * Created by milan on 20/04/17.
 */

Vue.directive('map', function (el, binding) {
  console.log(el.id);
return;
  // console.log(binding.value.id) // => "white"
  // console.log(binding.value.polyline)  // => "hello!"
  // source: http://doublespringlabs.blogspot.com.br/2012/11/decoding-polylines-from-google-maps.html
  var encoded = binding.value.polyline;
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
  var coordinates = points;
  // console.log(coordinates);
  var bounds = new google.maps.LatLngBounds();
  for (var i = 0; i < coordinates.length; i++) {
      bounds.extend(coordinates[i]);
  }
  var map = new google.maps.Map(el);
  map.fitBounds(bounds);
      
  var decodedPath = google.maps.geometry.encoding.decodePath(binding.value.polyline); 
  var setRegion = new google.maps.Polyline({
      path: decodedPath,
      strokeColor: "#FF0000",
      strokeOpacity: 1.0,
      strokeWeight: 2,
      map: map
  });
})

Vue.component('api-data', {
  template: '#api-data',
  
  created: function () { this.getData() },

  data: function () {
    return {
      apiURL: "",
      loader: false,
      search: "",
      data: [],
      page: 1,
      pages: 1,
      error: {
        message: ""
      }
    };
  },

  props: {
    apiurl: {
      type: String,
      required: true
    }
  },
  
  methods: {
    onSearchChange: _.debounce(function () { this.getData('current') }, 500),

    getData: function (rel) {
      var that = this;
      var apiurl = rel ? that.apiURL[rel] : that.apiurl;
      if (apiurl && apiurl !== "") {
        var url = URI(apiurl);
        if ( rel == "current" ) {
          url = url.search({q: this.search});
        }
        url = url.toString();

        that.loader = true;
        that.$http.get(url)
          .then(function (result) {
            if ( result.headers.get('Link') ) {
              this.apiURL = parseLinkHeader(result.headers.get('Link'));
            }
            that.loader = false;
            this.data = result.data;
          }, function (response, status, request) {
            that.loader = false;
            var data = response.data;
            if (data.message) {
              that.error.message = data.message;
            }
            else {
              that.error.message = "Oops Something went wrong, please try again later.";
            }
          })
          .finally(function () {
          });
      } else {
        console.log("No apiurl");
      }
    },

    currentPage: function () {
      var that = this;
      var page, total;
      var current = that.apiURL['current'];
      if (current && current !== "") {
        var search = URI(current).search(true);
        page = search['page'] || 1;
      } else {
        page = 1;
      }
      var end = that.apiURL['end'];
      if (end && end !== "") {
        var search = URI(end).search(true);
        total = search['page'] || 1;
      } else {
        total = 1;
      }
      return page + " / " + total;
    },

    getLink: function (rel) {
      return this.apiURL[rel];
    }

  }
});
