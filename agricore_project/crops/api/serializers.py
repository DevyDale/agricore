
from rest_framework import serializers
from ..models import CropCycle, CropUnit

class CropCycleSerializer(serializers.ModelSerializer):
	class Meta:
		model = CropCycle
		fields = '__all__'

	def validate(self, data):
		required_fields = ['crop_unit', 'crop_type', 'planting_date']
		missing = [f for f in required_fields if not data.get(f)]
		if missing:
			raise serializers.ValidationError({f: 'This field is required.' for f in missing})
		return data
