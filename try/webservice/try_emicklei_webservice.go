package webservice

import (
	webservice "github.com/emicklei/go-restful/v3"
	"log"
	"net/http"
)

type User struct {
	Id, Name string
}

func FindUser(request *webservice.Request, response *webservice.Response) {
	id := request.PathParameter("user-id")
	// here you would fetch user from some persistence system
	usr := &User{Id: id, Name: "John Doe"}
	response.WriteEntity(usr)
}

func UpdateUser(request *webservice.Request, response *webservice.Response) {
	usr := new(User)
	err := request.ReadEntity(&usr)
	// here you would update the user with some persistence system
	if err == nil {
		response.WriteEntity(usr)
	} else {
		response.WriteError(http.StatusInternalServerError, err)
	}
}

func CreateUser(request *webservice.Request, response *webservice.Response) {
	usr := User{Id: request.PathParameter("user-id")}
	err := request.ReadEntity(&usr)
	// here you would create the user with some persistence system
	if err == nil {
		response.WriteEntity(usr)
	} else {
		response.WriteError(http.StatusInternalServerError, err)
	}
}

func RemoveUser(request *webservice.Request, response *webservice.Response) {
	// here you would delete the user from some persistence system
}

func new111() *webservice.WebService {
	service := new(webservice.WebService)
	service.
		Path("/users").
		Consumes(webservice.MIME_XML, webservice.MIME_JSON).
		Produces(webservice.MIME_XML, webservice.MIME_JSON)

	service.Route(service.GET("/{user-id}").To(FindUser))
	service.Route(service.POST("").To(UpdateUser))
	service.Route(service.PUT("/{user-id}").To(CreateUser))
	service.Route(service.DELETE("/{user-id}").To(RemoveUser))

	return service
}

func Service() {
	webservice.Add(new111())
	log.Fatal(http.ListenAndServe(":8080", nil))
}
